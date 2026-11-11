import { logTag } from "../common/printLog";
import { watchHeightVp } from "../common/ScreenSize";
import { ScrollOffsetSampler } from "../common/ScrollOffsetSampler";
import { CardStackCard } from "./cardstack/CardStackCard";
import { cardPhaseAt, hasNextCard, normalizeScrollPosition } from "./cardstack/CardStackLayout";

/**
 * 卡片堆叠菜单：哔哩哔哩「更多」与抖音菜单共用。
 *
 * 巧妙点：Scroll 里一张卡片都没有，它只当"分页器 + 进度发生器"。
 *
 *   Stack
 *   ├── DownChevron                 下滑箭头
 *   ├── ForEach → CardStackCard     真正画出来的卡片（纯展示，不接手势）
 *   └── Scroll                      透明层，盖在最上面
 *         └── N × CardStackTouchLayer（每页一个全屏空白命中区）
 *
 * 按帧把 Scroll 偏移采样成 normalizedPosition（当前页号，带小数），
 * 再由 cardPhaseAt() 换算成每张卡的相位，卡片据此位移 / 缩小：
 * 新卡从屏下顶上来盖住当前页，当前页同时以中心为锚点缩进牌堆。
 *
 * 触摸被最上层的 Scroll 吃掉，由 CardStackTouchLayer 的两块空白区转发成
 * "点当前这张卡"和"翻到下一页"。好处是卡片不参与 Scroll 的布局测量，每帧只改
 * offset / scale 两个属性；甩动惯性与边缘回弹的落点也天然和卡片动画同源，
 * 不需要另配一条缓动曲线去追。
 */

/** 菜单项：卡片数据 + 点击后要去哪。 */
export interface CardInfo {
  title: string,
  svgIcon: Resource,
  gradientColors: [ResourceColor, number][],
  iconColor?: ResourceColor,
  onClick: (pageInfos: NavPathStack) => void
}

/** 箭头命中区高度；卡片点击区 = 屏高 - 这个值。 */
const CHEVRON_HIT_HEIGHT_VP: number = 42;
/** 箭头视觉尺寸与底距，原实现写的是 50px / 20px。 */
const CHEVRON_ICON_SIZE_VP: number = 25;
const CHEVRON_BOTTOM_MARGIN_VP: number = 10;
const CHEVRON_FADE_MS: number = 300;

/** 外页需要主动滚回顶部时用（如登录成功后回到第一张卡）。 */
export class StackWidgetPageScrollController {
  scroller: Scroller = new Scroller()

  scrollToTop(): void {
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: true
    })
  }
}

@ComponentV2
export struct StackWidgetPage {
  @Param @Require cardData: Array<CardInfo>
  @Param onNavReady: (context: NavDestinationContext) => void = () => {}
  @Param onNavShown: () => void = () => {}
  @Param scrollMod: StackWidgetPageScrollController = new StackWidgetPageScrollController()
  @Local private pageInfos: NavPathStack | null = null
  @Local private scrollOffsetY: number = 0
  private sampler: ScrollOffsetSampler =
    new ScrollOffsetSampler(() => this.readScrollOffset(), (offset: number) => {
      this.scrollOffsetY = offset
    })

  @Computed
  private get normalizedPosition(): number {
    return normalizeScrollPosition(this.scrollOffsetY, watchHeightVp)
  }

  @Computed
  private get showDownArrow(): boolean {
    return hasNextCard(this.normalizedPosition, this.cardData.length)
  }

  aboutToDisappear(): void {
    // 滚动途中被 pop 时定时器还活着，不停表就会对已销毁的组件继续采样。
    this.sampler.stop()
  }

  build() {
    NavDestination() {
      Stack() {
        DownChevron({ showChevron: this.showDownArrow })

        // 第一遍：画卡片。书写顺序即层级，index 大的后画、盖在上面。
        ForEach(this.cardData, (cardInfo: CardInfo, index: number) => {
          CardStackCard({
            title: cardInfo.title,
            icon: cardInfo.svgIcon,
            gradientColors: cardInfo.gradientColors,
            iconColor: cardInfo.iconColor || Color.White,
            phase: cardPhaseAt(this.normalizedPosition, index)
          })
        }, (cardInfo: CardInfo, index: number) => this.cardKey(index))

        // 第二遍：同一份数据铺一层透明命中区。Scroll 在最上层，卡片本身收不到触摸。
        Scroll(this.scrollMod.scroller) {
          Column() {
            ForEach(this.cardData, (cardInfo: CardInfo, index: number) => {
              CardStackTouchLayer({
                onCardClick: () => {
                  this.click(cardInfo, index)
                },
                onNextPage: () => {
                  this.scrollDown(index)
                }
              })
            }, (cardInfo: CardInfo, index: number) => this.cardKey(index))
          }
          .width('100%')
          .height(watchHeightVp * this.cardData.length)
        }
        .edgeEffect(EdgeEffect.Spring)
        .onScrollStart(() => {
          this.sampler.start()
        })
        .onScrollStop(() => {
          this.sampler.stop()
        })
        .enablePaging(true)
        .scrollBar(BarState.Off)
        // 支持表冠
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
        .height('100%')
        .width('100%')
      }
      .alignContent(Alignment.Center)
      // 触摸接收层和显示层不是同一个组件，所以把触摸反馈挂到最外层，对两者都生效。
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .height('100%')
      .width('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
      this.onNavReady(context)
    })
    .onShown(() => {
      this.onNavShown()
    })
  }

  /** 列表是静态数组，用下标做 key 就够；两层 ForEach 共用同一个 key。 */
  private cardKey(index: number): string {
    return index.toString()
  }

  /** Scroller 还没布局好或页面已销毁时会抛错，此时丢弃这一帧，保留上一个有效偏移。 */
  private readScrollOffset(): number | null {
    try {
      return this.scrollMod.scroller.currentOffset().yOffset
    } catch (error) {
      return null
    }
  }

  private scrollDown(index: number): void {
    const lastIndex: number = this.cardData.length - 1;
    if (index === lastIndex) {
      // 最后一页无法再往下翻页
      return;
    }
    const nextPage: number = index + 1;
    this.scrollMod.scroller.scrollTo({
      xOffset: 0,
      yOffset: watchHeightVp * nextPage,
      animation: true
    })
  }

  private click(cardInfo: CardInfo, index: number): void {
    console.debug(logTag, "点击了第" + (index + 1) + "张卡片")
    if (this.pageInfos !== null) {
      cardInfo.onClick(this.pageInfos)
    } else {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
    }
  }
}

/**
 * 一页一个的透明命中层：上半转发"点卡片"，下缘转发"翻下一页"。
 * 两块高度加起来正好一屏，滚动时不会露出接缝。
 */
@ComponentV2
struct CardStackTouchLayer {
  @Param @Require onCardClick: () => void
  @Param @Require onNextPage: () => void

  build() {
    Column() {
      // 对应可见卡片的触摸区域
      Column()
        .width('100%')
        .height(watchHeightVp - CHEVRON_HIT_HEIGHT_VP)
        .onClick(this.onCardClick)

      // 对应底下箭头的触摸区域
      Column()
        .width('100%')
        .height(CHEVRON_HIT_HEIGHT_VP)
        .onClick(this.onNextPage)
    }
    .width('100%')
    .height(watchHeightVp)
  }
}

@ComponentV2
struct DownChevron {
  @Param @Require showChevron: boolean

  build() {
    Column() {
      if (this.showChevron) {
        Image($r("app.media.chevron_down"))
          .width(CHEVRON_ICON_SIZE_VP)
          .height(CHEVRON_ICON_SIZE_VP)
          .margin({ bottom: CHEVRON_BOTTOM_MARGIN_VP })
          .transition(TransitionEffect.OPACITY.animation({ duration: CHEVRON_FADE_MS, curve: Curve.Smooth }))
      }
    }
    .justifyContent(FlexAlign.End)
    .width('100%')
    .height('100%')
  }
}
