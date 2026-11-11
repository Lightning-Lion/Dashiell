import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ArcScrollBar,
  ColorMetrics,
  curves,
  LengthMetrics,
} from "@kit.ArkUI"
import { logTag } from "../../common/printLog"
import { AppDatabase } from "../../common/storage/AppDatabase"
import { UUID } from "../../common/UUID"
import { ReadingSourcePagePushData } from "./NewsListPage"
import { LoggedInAtLeastOnceStore } from "../BiliLogout/BiliLogInOutPage"
import { webview } from '@kit.ArkWeb'
import { DarkTheme } from "../../common/Theme"
import { requestFocusWithRetry } from '../../common/WatchListFocus';
import { HeroOrigin, RSSHeroTransition, originFromClickEvent } from "../../common/RSSHeroTransition"

// 首页条目点进去的目标页，先算出来（哔哩哔哩还要查登录态），等 hero 展开成整屏后再真正 push
interface RouteIntent {
  name: string
  param: Object | undefined
}

// RSS 订阅列表的展示层条目：displayTitle 与 isPreset 来自下面内置的那张表，
// stableId 用来关联数据库里的订阅记录（顺序、启用状态）。
// 内置项（isPreset）不写库，是在 displayItems 里上屏前插进去的。
@ObservedV2
class RSSListEntry {
  @Trace
  stableId: string
  @Trace
  displayTitle: string
  @Trace
  isPreset: boolean

  constructor(stableId: string, displayTitle: string, isPreset: boolean) {
    this.stableId = stableId
    this.displayTitle = displayTitle
    this.isPreset = isPreset
  }

  listId(): string {
    // 确保同一个stableId的项目在从preset的变成用户主动添加的时候，会正确刷新视图，更新displayTitle
    if (this.isPreset) {
      return "84d78359-11ee-4dcd-8a8c-46f0a1165e18" + this.stableId
    } else {
      return "e883b2ab-19f4-4593-8a3b-da4cc5bef514" + this.stableId
    }
  }
}

interface URLToRSSItem {
  url: string
  rssItemStableId: string
}

@ObservedV2
class RSSSourceStore {
  @Trace
  enabledRSSItemsId: string[] = []
  private readonly model: URLEnterAndRSSListPageViewModel

  constructor(model: URLEnterAndRSSListPageViewModel) {
    this.model = model
  }

  async restoreFromDB(): Promise<void> {
    try {
      const db = await AppDatabase.open(getContext())
      this.enabledRSSItemsId = await db.rssSubscriptions.getAll()
      console.debug(logTag, "已保存了几个RSS源：", this.enabledRSSItemsId.length)
    } catch (error) {
      console.debug(logTag, "从数据库恢复已添加的RSS源失败：", RSSSourceStore.describe(error))
      this.model.component.getUIContext()
        .getPromptAction()
        .showToast({ message: "无法加载RSS源\n错误信息：数据库错误" })
    }
  }

  addNew(stableId: string, onDone: () => void) {
    (async () => {
      // 先在内存里更变完
      this.addOrMoveToFirst(stableId)
      // 然后持久化一下
      try {
        await this.save()
        onDone()
      } catch (error) {
        console.debug(logTag, "保存RSS源失败：", RSSSourceStore.describe(error))
        this.model.component.getUIContext()
          .getPromptAction()
          .showToast({ message: "无法保存RSS源\n错误信息：数据库错误" })
      }
    })()
  }

  private async save(): Promise<void> {
    const db = await AppDatabase.open(getContext())
    await db.rssSubscriptions.replaceOrder(this.enabledRSSItemsId)
  }

  private addOrMoveToFirst(item: string): void {
    // 找到元素在数组中的索引
    const index = this.enabledRSSItemsId.indexOf(item);

    if (index !== -1) {
      // 如果元素存在，先移除它
      this.enabledRSSItemsId.splice(index, 1);
    }

    // 添加到数组第一位
    this.enabledRSSItemsId.unshift(item);
  }

  async remove(item: string): Promise<void> {
    const index = this.enabledRSSItemsId.indexOf(item);
    if (index !== -1) {
      this.enabledRSSItemsId.splice(index, 1)
      try {
        await this.save()
      } catch (error) {
        console.debug(logTag, "删除RSS源失败：", RSSSourceStore.describe(error))
        this.model.component.getUIContext()
          .getPromptAction()
          .showToast({ message: "无法删除RSS源\n错误信息：数据库错误" })
      }
    } else {
      console.debug(logTag, "业务逻辑错误，外界传入了无效的item")
    }
  }

  private static describe(error: Object): string {
    const message = (error as Error).message
    return message === undefined ? 'unknown' : message
  }
}

@ObservedV2
class URLEnterAndRSSListPageViewModel {
  @Trace
  cleanTextInputToken: string = UUID();
  @Trace
  private allRSSSource: RSSListEntry[] = [
    new RSSListEntry(
      "f8065df0-709e-488e-844f-a0a3da398c00",
      "【非官方】哔哩哔哩RSS",
      false
    ),
    new RSSListEntry(
      "b0dae50d-834e-461a-887b-0feb465b59b2",
      "【非官方】抖音RSS",
      false
    ),
    new RSSListEntry(
      "98512980-db1b-4247-8cab-a04747a899e8",
      "3DM - 新闻中心",
      false
    ),
    new RSSListEntry(
      "8e9ae28e-2386-488e-879d-ed88e331eb5a",
      "IT之家",
      false
    ),
    new RSSListEntry(
      "021004af-7a91-43af-b4d8-29137c8a757c",
      "知乎日报",
      false
    ),
    new RSSListEntry(
      "0e229179-64a1-416f-811d-3ddf22b91b2d",
      "知乎热榜",
      false
    ),
  ]
  @Trace
  private defaultList: RSSListEntry[] = [
    new RSSListEntry(
      "98512980-db1b-4247-8cab-a04747a899e8",
      "游戏资讯",
      true
    ),
    new RSSListEntry(
      "8e9ae28e-2386-488e-879d-ed88e331eb5a",
      "科技资讯",
      true
    ),
    new RSSListEntry(
      "021004af-7a91-43af-b4d8-29137c8a757c",
      "知识资讯",
      true
    ),
  ]
  @Trace
  private findByStableId = (
    items: RSSListEntry[],
    targetStableId: string
  ): RSSListEntry | null =>
  items.find(item => item.stableId === targetStableId) ?? null;

  @Computed
  get displayItems(): RSSListEntry[] {
    if (this.store.enabledRSSItemsId.length === 0) {
      return this.defaultList
    }

    const finalList: RSSListEntry[] = []
    // 把每个StableId找到对应的源
    this.store.enabledRSSItemsId.forEach((stableId: string) => {
      const rssItem: RSSListEntry | null = this.findByStableId(this.allRSSSource, stableId);
      if (rssItem !== null) {
        console.debug(logTag, "添加了" + rssItem.displayTitle)
        finalList.push(rssItem)
      } else {
        console.debug(logTag, "遇到了一个找不到匹配项的StableID：", stableId)
      }
    })
    // 看来数据库里保存的全是一堆没用的
    if (finalList.length === 0) {
      console.debug(logTag, "finalList长度：" + finalList.length)
      return this.defaultList
    } else {
      // 伪造“加了自定义RSS源，不破坏预设RSS源”的效果
      // 遍历每个defaultList项目，如果在finalList里缺少对应的项目，就也加入进去
      this.defaultList.forEach((presetItem) => {
        const presetItemStableId: string = presetItem.stableId
        if (finalList.find((sustainItem) => {
          return sustainItem.stableId === presetItemStableId
        })) {
          // 数据库里已经包含了这个预设源了，不用加了
        } else {
          // 这个预设源还需要继续显示
          // 也加入最终上屏的项目
          finalList.push(presetItem)
        }
      })
    }
    console.debug(logTag, "返回了finalList")
    return finalList
  }

  @Computed
  get deletableItemCount(): number {
    return this.store.enabledRSSItemsId.length
  }

  @Trace
  private store = new RSSSourceStore(this)
  readonly component: CustomComponent

  constructor(component: CustomComponent) {
    this.component = component
  }

  aboutToAppear() {
    const _: Promise<void> = this.store.restoreFromDB()
  }

  @Trace
  private insertableURLs: URLToRSSItem[] = [
    {
      url: "https://rss.dashiell.cn/",
      rssItemStableId: "f8065df0-709e-488e-844f-a0a3da398c00"
    },
    {
      url: "https://rss.dashiell.cn/bilibili/weekly/",
      rssItemStableId: "f8065df0-709e-488e-844f-a0a3da398c00"
    },
    {
      url: "https://www.douyin.com/",
      rssItemStableId: "b0dae50d-834e-461a-887b-0feb465b59b2"
    },
    {
      url: "https://rss.dashiell.cn/3dmgame/news/",
      rssItemStableId: "98512980-db1b-4247-8cab-a04747a899e8"
    },
    {
      url: "https://www.ithome.com/rss/",
      rssItemStableId: "8e9ae28e-2386-488e-879d-ed88e331eb5a"
    },
    {
      url: "https://rss.dashiell.cn/zhihu/daily/",
      rssItemStableId: "021004af-7a91-43af-b4d8-29137c8a757c"
    },
    {
      url: "https://rss.dashiell.cn/zhihu/hot/",
      rssItemStableId: "0e229179-64a1-416f-811d-3ddf22b91b2d"
    }
  ]
  @Trace
  private findByUrl = (
    items: URLToRSSItem[],
    targetUrl: string
  ): URLToRSSItem | null =>
  items.find(item => {
    // 确保完全匹配，因为哔哩哔哩RSS实际上也是其它RSS源的前缀
    return targetUrl === item.url
  }) ?? null;

  tryToAddNewRSSSource(url: string) {
    if (!url) {
      this.component.getUIContext().getPromptAction().showToast({
        message: "" +
          "请输入或粘贴RSS源"
      })
      return
    }
    const result: URLToRSSItem | null = this.findByUrl(this.insertableURLs, url)
    if (result === null) {
      this.component.getUIContext().getPromptAction().showToast({
        message: "" +
          "请输入或粘贴RSS源"
      })
      return
    }
    const stableId: string = result.rssItemStableId
    this.store.addNew(stableId, () => {
      this.cleanTextInputToken = UUID();
      // 仅在成功的时候调用
      this.component.getUIContext().getPromptAction().showToast({ message: "添加成功" })
    })
  }

  deleteRSSSource(stableId: string) {
    // 外界有责任只传入非isPreset的RSSListEntry，因为业务逻辑不允许删掉内置的RSSListEntry
    // 因为内置的RSSListEntry们不是真的存储在数据库，而是在上屏前，在displayItems里强制插入的
    // 如果要删，需要改displayItems计算属性的逻辑

    // 因为按钮需要同步函数，这边简单包装一下
    (async () => {
      await this.store.remove(stableId)
    })()
  }
}

@ComponentV2
export struct HomePageRSSList {
  @Param @Require pageInfos: NavPathStack
  // 一镜到底 + 交叉渐变转场；画面由 NavigationStack 里的 RSSHeroTransitionOverlay 承担
  @Param @Require hero: RSSHeroTransition
  @Local
  private vm: URLEnterAndRSSListPageViewModel = new URLEnterAndRSSListPageViewModel(this)
  @Local
  private scroller: Scroller = new Scroller()
  @Local
  private loggedInAtLeastOnceStore: LoggedInAtLeastOnceStore = new LoggedInAtLeastOnceStore()
  @Local
  private pageID: string = UUID()
  @Local
  private isInLongPressMode: boolean = false
  // 第一步，创建TransitionEffect
  private deleteButtonTransitionEffect: TransitionEffect =
    // 创建默认透明度转场效果,并指定了springMotion(0.6, 0.8)曲线
    TransitionEffect.OPACITY.animation({
      curve: curves.springMotion(0.6, 0.8)
    })// 通过combine方法,这里的动画参数会跟随上面的TransitionEffect，也就是springMotion(0.6, 0.8)
      .combine(TransitionEffect.scale({
        x: 0,
        y: 0
      }))// 添加旋转转场效果，这里的动画参数会跟随上面带animation的TransitionEffect，也就是springMotion(0.6, 0.8)
      .combine(TransitionEffect.rotate({ angle: 90 }))// 添加平移转场效果，这里的动画参数使用指定的springMotion()
      .combine(TransitionEffect.translate({ y: 150 })
        .animation({ curve: curves.springMotion() }))// 添加move转场效果，这里的动画参数会跟随上面的TransitionEffect，也就是springMotion()
      .combine(TransitionEffect.move(TransitionEdge.END))

  build() {
    Column() {
      Stack({ alignContent: Alignment.End }) {
        List({ space: "0fp", scroller: this.scroller }) {
          ListItem() {
            Column() {
              IconView({ pageID: this.pageID })
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width("100%")
          }
          .onClick(() => {
          })
          .padding({
            bottom: LengthMetrics.fp(12)
          })

          ListItem() {
            Column() {
              URLEnterView({
                onTapSearch: (url: string) => {
                  this.vm.tryToAddNewRSSSource(url)
                },
                cleanTextInputToken: this.vm.cleanTextInputToken,
                pageID: this.pageID
              })
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width("100%")
          }
          .padding({
            bottom: LengthMetrics.fp(12)
          })

          ListItem() {
            Column() {
              TipView()
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width("100%")
          }
          .padding({
            bottom: LengthMetrics.fp(12)
          })

          ForEach(this.vm.displayItems, (item: RSSListEntry) => {
            // 业务逻辑：修复首页可添加资讯，无法删除资讯的问题
            HomePageRSSListRow({
              displayTitle: item.displayTitle,
              onButtonClick: (origin: HeroOrigin | null) => {
                this.startSourceEntry(item, origin)
              },
              onLongPress: () => {
                if (item.isPreset === true) {
                  // 不能删预置项目，什么也不做
                } else {
                  // 进入删除模式
                  this.isInLongPressMode = true
                }
              },
              isInLongPressMode: this.isInLongPressMode,
              deletable: !item.isPreset, // 不能删除预置项目
              onDeleteButtonClick: () => {
                // 检查删除后是否还有可删除的项
                const willRemainDeletableItems = this.vm.deletableItemCount > 1

                // 这个里面是异步操作删除的
                this.vm.deleteRSSSource(item.stableId)

                // 如果删除后没有可删除的项了，退出长按模式
                if (!willRemainDeletableItems) {
                  this.isInLongPressMode = false
                }
              }
            })
          }, (item: RSSListEntry) => item.listId())


          HomePageRSSListRow({
            displayTitle: "🔥发现更多",
            onButtonClick: (origin: HeroOrigin | null) => {
              this.startFindMoreEntry(origin)
            },
            isInLongPressMode: this.isInLongPressMode,
            deletable: false,
          })
          about(this.pageInfos)
          icpNumber(this.pageInfos)
        }
        // 样式
        .chainAnimation(true)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        // 焦点
        .onAppear(() => {
          try {
            requestFocusWithRetry(this.getUIContext(), this.pageID + "dbe932dc-fcd1-451b-b5ad-f825dd3c59ee")
          } catch (error) {
            console.debug(logTag, 'requestFocus failed code is ' + error.code + ' message is ' + error.message)
          }
        })
        .id(this.pageID + "dbe932dc-fcd1-451b-b5ad-f825dd3c59ee")
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
        // 布局
        .contentStartOffset(55)
        .contentEndOffset(46)
        .padding({ left: 16, right: 16 })
        .width('100%')
        .height("100%")

        if (this.isInLongPressMode) {
          Row() {
            ArcButton({
              options: new ArcButtonOptions({
                label: "退出编辑",
                backgroundColor: ColorMetrics.resourceColor($r("app.color.DestructiveButtonColor")),
                position: ArcButtonPosition.BOTTOM_EDGE,
                styleMode: ArcButtonStyleMode.CUSTOM,
                shadowEnabled: true,
                shadowColor: ColorMetrics.rgba(233, 76, 70, 0.4),
                onClick: () => this.isInLongPressMode = false
              })
            })
          }.position({ bottom: 0, left: 0 })
          .width("100%")
          .justifyContent(FlexAlign.Center)
          .transition(this.deleteButtonTransitionEffect)
        }

        ArcScrollBar({ scroller: this.scroller })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
    // 首页不是 NavDestination，渐变只能挂在自己的根容器上
    .linearGradient({ colors: DarkTheme.pageTopGradients.brand })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.Smooth }))
    .onAppear(() => {
      // 从数据库持久化中恢复
      this.vm.aboutToAppear()
    })
  }

  /** 点了某个 RSS 源：开始一镜到底，同时并行解析目标页。 */
  private startSourceEntry(item: RSSListEntry, origin: HeroOrigin | null): void {
    if (this.isInLongPressMode || this.hero.isRunning()) {
      return
    }
    // 先发起路由解析（哔哩哔哩要查登录态），把这段等待藏进展开动画里
    const intent: Promise<RouteIntent | null> = this.resolveRoute(item)
    const _: Promise<void> = this.hero.begin({
      title: item.displayTitle,
      origin: origin,
      commit: () => this.commitRoute(intent)
    })
  }

  /** 点了「发现更多」：同样的转场，目标页是固定的。 */
  private startFindMoreEntry(origin: HeroOrigin | null): void {
    if (this.isInLongPressMode || this.hero.isRunning()) {
      return
    }
    const _: Promise<void> = this.hero.begin({
      title: "🔥发现更多",
      origin: origin,
      commit: async (): Promise<boolean> => {
        // 推页由 customNavContentTransition 接管：目标页直接落位，hero 淡出时交叉渐变
        this.pageInfos.pushPathByName("FindMoreRSSPage", undefined, true)
        return true
      }
    })
  }

  /** 只算去哪，不 push；真正 push 要等 hero 展开成整屏。 */
  private async resolveRoute(item: RSSListEntry): Promise<RouteIntent | null> {
    switch (item.stableId) {
      case "f8065df0-709e-488e-844f-a0a3da398c00": { //哔哩哔哩
        let isLoggedInAtLeastOnce: boolean = await this.loggedInAtLeastOnceStore.isLoggedInAtLeastOnce()
        if (!isLoggedInAtLeastOnce) {
          try {
            webview.WebviewController.initializeWebEngine()
            const cookie = await webview.WebCookieManager.fetchCookie('https://www.bilibili.com/')
            isLoggedInAtLeastOnce = /(^|;\s*)SESSDATA=[^;]+/.test(cookie || '')
          } catch (_) {
            isLoggedInAtLeastOnce = false
          }
        }
        const route: RouteIntent = {
          // 用户都发现登录功能了，放心让用户登录
          name: isLoggedInAtLeastOnce ? "BiliHomeFeedPageWithLogin" : "BiliHomeFeedPageWithoutLogin",
          param: undefined
        }
        return route
      }
      case "b0dae50d-834e-461a-887b-0feb465b59b2": { // 抖音
        const route: RouteIntent = { name: "DouYinMenu", param: undefined }
        return route
      }
      case "98512980-db1b-4247-8cab-a04747a899e8": { //3DM
        const pushData0: ReadingSourcePagePushData = {
          displayTitle: "3DM - 新闻中心",
          sourceURL: "https://rss.dashiell.cn/3dmgame/news",
        }
        const route: RouteIntent = { name: "ReadingSourcePage", param: pushData0 }
        return route
      }
      case "8e9ae28e-2386-488e-879d-ed88e331eb5a": { //IT之家
        const pushData1: ReadingSourcePagePushData = {
          displayTitle: "IT之家",
          sourceURL: "https://www.ithome.com/rss/"
        }
        const route: RouteIntent = { name: "ReadingSourcePage", param: pushData1 }
        return route
      }
      case "021004af-7a91-43af-b4d8-29137c8a757c": { //知乎日报
        const pushData2: ReadingSourcePagePushData = {
          displayTitle: "知乎日报",
          sourceURL: "https://rss.dashiell.cn/zhihu/daily"
        }
        const route: RouteIntent = { name: "ReadingSourcePage", param: pushData2 }
        return route
      }
      case "0e229179-64a1-416f-811d-3ddf22b91b2d": { //知乎热榜
        const pushData: ReadingSourcePagePushData = {
          displayTitle: "知乎热榜 - 全站",
          sourceURL: "https://rss.dashiell.cn/zhihu/hot"
        }
        const route: RouteIntent = { name: "ReadingSourcePage", param: pushData }
        return route
      }
      default:
        return null
    }
  }

  /** hero 已经全屏后才真正 push；返回 false 时 hero 淡出、退回首页。 */
  private async commitRoute(intentPromise: Promise<RouteIntent | null>): Promise<boolean> {
    let intent: RouteIntent | null = null
    try {
      intent = await intentPromise
    } catch (error) {
      console.warn(logTag, 'RSS 首页路由解析失败：', JSON.stringify(error))
      intent = null
    }
    if (intent === null) {
      this.getUIContext().getPromptAction().showToast({ message: "无法打开页面\n错误原因：损坏的RSS源" })
      return false
    }
    // animated=true 才能让 customNavContentTransition 接管；
    // 实际不跑系统推入动画，目标页直接落位，由 hero 淡出完成交叉渐变
    this.pageInfos.pushPathByName(intent.name, intent.param, true)
    return true
  }
}

@ComponentV2
struct IconView {
  @Param @Require pageID: string
  @Local
  private iconDiameter: number = 55

  build() {
    Image($r("app.media.icon_for_rss_list"))
      .syncLoad(true)
      .objectFit(ImageFit.Auto)
      .borderRadius((this.iconDiameter / 2) + "fp")
      .width(this.iconDiameter + "fp")
      .height(this.iconDiameter + "fp")
      .focusable(true)
      .id(this.pageID + "6179d32b-edb8-4af8-aba8-8643b6e8fa1c")
  }
}

@ComponentV2
struct URLEnterView {
  @Param @Require onTapSearch: (url: string) => void
  @Param @Require cleanTextInputToken: string
  @Param @Require pageID: string

  @Monitor("cleanTextInputToken")
  onReceiveCleanTextInputToken() {
    console.debug(logTag, "onReceiveCleanTextInputToken")
    this.url = ""
  }

  @Local
  private url: string = ""
  @Local
  private searchButtonDiameter: number = 41

  build() {
    Stack({
      alignContent: Alignment.End
    }) {
      TextInput({ placeholder: "输入RSS源", text: $$this.url })
        .type(InputType.URL)
        // 避免页面一得焦就拉起键盘
        .enableKeyboardOnFocus(false)
        .fontColor(Color.Black)
        .placeholderColor("#6E6E69")
        .placeholderFont({
          size: "14fp"
        })
        .onBlur(() => {
          requestFocusWithRetry(this.getUIContext(), this.pageID + "6179d32b-edb8-4af8-aba8-8643b6e8fa1c")
        })
        .backgroundColor(Color.White)
      Button({
        type: ButtonType.Normal,
        role: ButtonRole.NORMAL,
        buttonStyle: ButtonStyleMode.NORMAL,
        stateEffect: true
      }) {
        Image($r("app.media.search_button"))
          .objectFit(ImageFit.Auto)
          .width(this.searchButtonDiameter + "fp")
          .height(this.searchButtonDiameter + "fp")
      }
      .borderRadius((this.searchButtonDiameter / 2) + "fp")
      .backgroundColor(Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.onTapSearch(this.url)
      })
    }
    .width("96%")
  }
}

@ComponentV2
struct TipView {
  build() {
    Text("请滑到最下方“发现更多”中，复制第一个RSS")
      .textOverflow({
        overflow: TextOverflow.MARQUEE
      })
      .padding({
        start: LengthMetrics.fp(10),
        end: LengthMetrics.fp(10),
      })
  }
}

@ComponentV2
struct HomePageRSSListRow {
  @Param @Require displayTitle: string
  // 带上被点卡片的窗口矩形，用于一镜到底的起点；量不到时为 null
  @Param @Require onButtonClick: (origin: HeroOrigin | null) => void
  @Param @Require isInLongPressMode: boolean
  @Param deletable: boolean = true
  @Param onLongPress: () => void = () => {
  }
  @Param onDeleteButtonClick: () => void = () => {
  }

  build() {
    ListItem() {
      Button() {
        Column() {
          Row({ space: "13fp" }) {
            if (this.isInLongPressMode && this.deletable) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark')).fontColor([Color.White]).fontWeight(FontWeight.Bold)
              }.backgroundColor($r("app.color.DestructiveButtonColor"))
              .padding(8)
              .transition(TransitionEffect.SLIDE_SWITCH.combine(TransitionEffect.OPACITY)
                .animation({ duration: 300, curve: Curve.Smooth }))
            } else {
              Image($r("app.media.rss_icon"))
                .objectFit(ImageFit.Auto)
                .width("32fp")
                .height("32fp")
                .transition(TransitionEffect.SLIDE_SWITCH.combine(TransitionEffect.OPACITY)
                  .animation({ duration: 300, curve: Curve.Smooth }))
            }
            // 文字太短靠左对齐，文字太长滚动
            Row({ space: "0fp" }) {
              Text(this.displayTitle)
                .fontSize(16)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Medium)
                .textOverflow({ overflow: TextOverflow.MARQUEE })
              Blank()
            }
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding({
          start: LengthMetrics.fp(16),
          end: LengthMetrics.fp(16)
        })
        .width('100%')
      }
      .backgroundColor(DarkTheme.cardBackground)
      .padding({
        top: LengthMetrics.fp(16),
        bottom: LengthMetrics.fp(16)
      })
      .borderRadius(16)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick((event: ClickEvent) => {
        if (this.isInLongPressMode === true) {
          if (this.deletable === true) {
            this.onDeleteButtonClick()
          } else {
            // 不是可删除的，什么都不用做
          }
        } else {
          this.onButtonClick(originFromClickEvent(event))
        }
      })
      .width('100%')
    }
    .padding({
      bottom: LengthMetrics.fp(12)
    })
    .gesture(
      LongPressGesture().onAction(() => {
        this.onLongPress()
      })
    )
  }
}


@Builder
function about(pageInfos: NavPathStack) {
  ListItem() {
    // 仅在下方提供额外触摸范围
    Button("关于", { type: ButtonType.ROUNDED_RECTANGLE, stateEffect: false })
      .fontSize("13.5fp")
      .width("100%")
      .padding({
        bottom: LengthMetrics.fp(8)
      })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        pageInfos.pushPathByName("AboutPage", undefined)
      })
      .backgroundColor(Color.Transparent)
  }
}


@Builder
function icpNumber(pageInfos: NavPathStack) {
  ListItem() {
    // 不提供额外扩展触摸范围
    Button("浙ICP备00000000号-1A", { type: ButtonType.ROUNDED_RECTANGLE, stateEffect: false })
      .fontSize("13.5fp")
      .width("100%")
      .height("13.5fp")
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        pageInfos.pushPathByName("BeianQrPage", undefined)
      })
      .backgroundColor(Color.Transparent)
  }
  .padding({
    bottom: LengthMetrics.fp(12)
  })
}
