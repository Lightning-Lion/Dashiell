import { BusinessError, pasteboard } from '@kit.BasicServicesKit'
import { logTag } from '../../common/printLog'
import { DarkTheme } from '../../common/Theme'

// 精选播放页右下角悬浮按钮进入的「下一页菜单」。
// 单独成页（NavDestination），而不是浮层，是为了把三项功能各拆到清晰的入口：
// 一、退出精选；二、复制当前播放视频标题（再跳文本选择页）；三、查看使用交互指引。

/** 精选菜单的入参：进入菜单那一刻，正在播放视频的标题快照。 */
export interface DouYinJingxuanMenuPushData {
  title: string
}

/** 文本选择/复制页的入参：要展示、可复制的视频标题。 */
export interface DouYinVideoTitleCopyPushData {
  title: string
}

// ============================ 一、精选菜单页 ============================

@Builder
export function DouYinJingxuanMenuBuilder(name: string, param: Object) {
  DouYinJingxuanMenu({
    title: (param as DouYinJingxuanMenuPushData)?.title ?? ''
  })
}

@ComponentV2
export struct DouYinJingxuanMenu {
  @Param title: string = ''
  @Local
  private pageInfos: NavPathStack | null = null

  /** 退出精选：菜单页是压在精选页之上的，直接回落到进入精选前的抖音菜单。 */
  private exitJingxuan(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
      return
    }
    // 与精选页悬浮按钮一致的做法：弹出到 DouYinMenu，连带把精选页和菜单页一起退出
    this.pageInfos.popToName("DouYinMenu")
  }

  /** 复制标题：导航到文本选择页，标题由那一页负责展示与复制。 */
  private goCopyTitle(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
      return
    }
    const pushData: DouYinVideoTitleCopyPushData = { title: this.title }
    this.pageInfos.pushPathByName("DouYinVideoTitleCopy", pushData)
  }

  /** 查看使用交互指引。 */
  private goGuide(): void {
    if (this.pageInfos === null) {
      this.getUIContext().getPromptAction().showToast({ message: "NavPathStack未挂载" })
      return
    }
    this.pageInfos.pushPathByName("DouYinInteractionGuide", undefined)
  }

  build() {
    NavDestination() {
      Column({ space: "10vp" }) {
        Text("精选菜单")
          .fontSize("18fp")
          .fontWeight(FontWeight.Bold)
          .fontColor(DarkTheme.textPrimary)
          .margin({ top: "12vp", bottom: "2vp" })
        DouYinMenuEntry({ label: "退出精选", onTap: () => this.exitJingxuan() })
        DouYinMenuEntry({ label: "复制视频标题", onTap: () => this.goCopyTitle() })
        DouYinMenuEntry({ label: "使用指引", onTap: () => this.goGuide() })
      }
      .width("100%")
      .height("90%")
      .padding({ left: "10vp", right: "10vp", bottom: "12vp" })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不铺不透明底色，否则会盖住它
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}

// 菜单里的一行按钮。样式对齐关于页(AboutPage)：统一深灰胶囊 + 白字，
// 用低调的中性色压住高饱和强调色，戴在手腕上更耐看；焦点相关属性照搬关于页以支持表冠。
@ComponentV2
struct DouYinMenuEntry {
  @Param @Require label: string
  @Param @Require onTap: () => void

  build() {
    Button(this.label, { type: ButtonType.Capsule })
      .fontSize("15fp")
      .fontColor(DarkTheme.textPrimary)
      .backgroundColor(DarkTheme.textFieldBackground)
      .width("100%")
      .height("42vp")
      .focusable(true)
      .focusOnTouch(true)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => {
        this.onTap()
      })
  }
}

// ============================ 二、文本选择 / 复制页 ============================

@Builder
export function DouYinVideoTitleCopyBuilder(name: string, param: Object) {
  DouYinVideoTitleCopy({
    title: (param as DouYinVideoTitleCopyPushData)?.title ?? ''
  })
}

@ComponentV2
export struct DouYinVideoTitleCopy {
  @Param title: string = ''
  @Local
  private pageInfos: NavPathStack | null = null

  /** 写系统剪贴板。与 RSS 发现页的复制实现保持一致。 */
  private copyToPasteboard(text: string): void {
    (async () => {
      try {
        const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
        const systemPasteboard = pasteboard.getSystemPasteboard()
        await systemPasteboard.setData(pasteboardData)
        this.getUIContext().getPromptAction().showToast({ message: "已复制标题", duration: 1000 })
      } catch (error) {
        const typedError: BusinessError = error
        console.debug(logTag, "复制标题失败：" + typedError.message)
        this.getUIContext().getPromptAction().showToast({ message: typedError.message })
      }
    })()
  }

  build() {
    NavDestination() {
      Column({ space: "10vp" }) {
        Text("视频标题")
          .fontSize("18fp")
          .fontWeight(FontWeight.Bold)
          .fontColor(DarkTheme.textPrimary)
          .margin({ top: "12vp" })
        if (this.title.length === 0) {
          Text("没有取到标题，可能当前没有正在播放的视频")
            .fontSize("14fp")
            .fontColor(DarkTheme.textSecondary)
            .textAlign(TextAlign.Center)
            .margin({ top: "20vp" })
        } else {
          // 文本选择区：长按/框选后可用系统复制条，下方再给一个整条复制按钮
          Scroll() {
            Text(this.title)
              .fontSize("15fp")
              .fontColor(DarkTheme.textPrimary)
              .textAlign(TextAlign.Start)
              .copyOption(CopyOptions.InApp)
              .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
              .draggable(true)
              .padding("12vp")
              .width("100%")
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .align(Alignment.TopStart)
          // 半透明卡片，让 NavDestination 的顶部渐变透出来
          .backgroundColor('#66000000')
          .borderRadius("8vp")
          .width("100%")

          Button("复制标题", { type: ButtonType.Capsule })
            .fontSize("15fp")
            .fontColor(DarkTheme.textPrimary)
            .backgroundColor(DarkTheme.textFieldBackground)
            .width("100%")
            .height("42vp")
            .focusable(true)
            .focusOnTouch(true)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.copyToPasteboard(this.title)
            })
        }
      }
      .width("100%")
      .height("100%")
      .padding({ left: "10vp", right: "10vp", bottom: "12vp" })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不铺不透明底色，否则会盖住它
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}

// ============================ 三、使用交互指引页 ============================

@Builder
export function DouYinInteractionGuideBuilder(name: string, param: Object) {
  DouYinInteractionGuide()
}

@ComponentV2
export struct DouYinInteractionGuide {
  @Local
  private pageInfos: NavPathStack | null = null

  build() {
    NavDestination() {
      Column({ space: "10vp" }) {
        Text("使用指引")
          .fontSize("18fp")
          .fontWeight(FontWeight.Bold)
          .fontColor(DarkTheme.textPrimary)
          .margin({ top: "12vp" })
        Scroll() {
          Column({ space: "14vp" }) {
            DouYinGuideRow({ symbol: "↕", text: "上下滑动切换视频" })
            DouYinGuideRow({ symbol: "⏯", text: "点击屏幕暂停 / 继续" })
            DouYinGuideRow({ symbol: "⛶", text: "双击全屏适应" })
          }
          .width("100%")
          .padding("12vp")
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.TopStart)
        // 半透明卡片，让 NavDestination 的顶部渐变透出来
        .backgroundColor('#66000000')
        .borderRadius("8vp")
        .width("100%")
      }
      .width("100%")
      .height("100%")
      .padding({ left: "10vp", right: "10vp", bottom: "12vp" })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
    .hideTitleBar(true)
    // 顶部渐变由 NavDestination 承载，内容层不铺不透明底色，否则会盖住它
    .linearGradient({ colors: DarkTheme.pageTopGradients.douyin })
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}

// 指引里的一条：左侧一个符号，右侧说明文字。
@ComponentV2
struct DouYinGuideRow {
  @Param @Require symbol: string
  @Param @Require text: string

  build() {
    Row({ space: "10vp" }) {
      Text(this.symbol)
        .fontSize("20fp")
        .fontColor(DarkTheme.accents.douyin)
        .width("30vp")
        .textAlign(TextAlign.Center)
      Text(this.text)
        .fontSize("15fp")
        .fontColor(DarkTheme.textPrimary)
        .layoutWeight(1)
    }
    .width("100%")
    .alignItems(VerticalAlign.Center)
  }
}
