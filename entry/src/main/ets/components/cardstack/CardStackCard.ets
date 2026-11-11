import { watchHeightVp } from '../../common/ScreenSize';
import { cardOffsetVpAt, cardScaleAt } from './CardStackLayout';

/**
 * 叠加层里的一张卡：只吃展示字段，不依赖 CardInfo。
 *
 * 这样卡片文件不需要反向 import 页面文件，依赖方向保持单向：
 * StackWidgetPage → CardStackCard → CardStackLayout。
 *
 * 卡片不接手势、也不接滚动偏移：phase 由页面按 cardPhaseAt() 算好传进来，
 * 卡片自己只回答"我该落在哪、缩到多大"。
 */

/** 卡片面尺寸。原实现写的是 px（330/300），466px = 233vp 下等价于 165/150vp。 */
const CARD_FACE_WIDTH_VP: number = 165;
const CARD_FACE_HEIGHT_VP: number = 150;
const CARD_FACE_RADIUS_VP: number = 16;
const CARD_FACE_GRADIENT_ANGLE: number = 45;

const CARD_ICON_SIZE_VP: number = 48;
const CARD_ICON_TITLE_GAP_VP: number = 16;
const CARD_TITLE_FONT_SIZE_VP: number = 18;

@ComponentV2
export struct CardStackCard {
  @Param @Require title: string;
  @Param @Require icon: Resource;
  @Param @Require gradientColors: [ResourceColor, number][];
  @Param iconColor: ResourceColor = Color.White;
  /** 相位：1 = 最前台，>1 已被翻过去（缩小），<1 还在屏下等着顶上来。 */
  @Param @Require phase: number;

  @Computed
  private get topOffsetVp(): number {
    return cardOffsetVpAt(this.phase, watchHeightVp);
  }

  @Computed
  private get scaleRatio(): number {
    return cardScaleAt(this.phase);
  }

  build() {
    Column() {
      CardStackCardFace({
        title: this.title,
        icon: this.icon,
        gradientColors: this.gradientColors,
        iconColor: this.iconColor
      })
        .offset({ top: this.topOffsetVp })
        .scale({ x: this.scaleRatio, y: this.scaleRatio })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height('100%')
    .width('100%')
  }
}

/** 卡片外观本身：渐变底 + 白图标 + 标题。 */
@ComponentV2
struct CardStackCardFace {
  @Param @Require title: string;
  @Param @Require icon: Resource;
  @Param @Require gradientColors: [ResourceColor, number][];
  @Param @Require iconColor: ResourceColor;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(CARD_FACE_RADIUS_VP)
        .linearGradient({
          angle: CARD_FACE_GRADIENT_ANGLE,
          colors: this.gradientColors,
          repeating: false
        })

      Column({ space: CARD_ICON_TITLE_GAP_VP }) {
        Image(this.icon)
          .width(CARD_ICON_SIZE_VP)
          .height(CARD_ICON_SIZE_VP)
          .objectFit(ImageFit.Contain)
          .fillColor(this.iconColor)

        Text(this.title)
          .fontSize(CARD_TITLE_FONT_SIZE_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(CARD_FACE_WIDTH_VP)
    .height(CARD_FACE_HEIGHT_VP)
  }
}
