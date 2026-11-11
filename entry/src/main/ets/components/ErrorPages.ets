import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ArcScrollBar,
  ColorMetrics,
  LengthMetrics
} from "@kit.ArkUI";
import { SettingsButton } from "../common/SettingsButton";
import { DarkTheme } from "../common/Theme";


export interface ErrorPromptData {
  errorMessage: string
  errorCode: string | null
}

/**
 * 错误提示组件
 * 用于显示错误信息并提供重试选项
 * onRetry 和 onClose 是可选的回调函数
 */
@Entry
@ComponentV2
export struct ErrorPrompt {
  @Param @Require errorMessage: string
  @Param errorCode: string | null = null
  @Param @Require showRetryButton: boolean = true
  @Param @Require showCloseButton: boolean = true
  @Param onRetry?: () => void = undefined
  @Param onClose?: () => void = undefined
  @Local private scroller: Scroller = new Scroller()

  build() {
    Stack() {
      Column() {
        // 半透明遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN)
          .position({ x: 0, y: 0 })
          .onClick(() => {
            this.onClose && this.onClose()
          })

        // 错误提示卡片
        Scroll(this.scroller) {
          Column() {
            // 错误标题
            Text('出错了')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .margin({ top: 20, bottom: 12 })

            // On a watch, actions take precedence over a large decorative icon.
            if (!this.showRetryButton && !this.showCloseButton) {
            Image($r('app.media.error_icon'))
              .width(60)
              .height(60)
              .margin({ bottom: 16 })
              .objectFit(ImageFit.Contain)
              .alt('错误图标')
            }

            // 错误信息
            Text(this.errorMessage)
              .fontSize(16)
              .margin({ bottom: 8 })
              .textAlign(TextAlign.Center)
              .padding({ left: 20, right: 20 })

            if (this.errorCode) {
              // 错误代码
              Text(`错误代码: ${this.errorCode}`)
                .fontSize(14)
                .fontColor('#888888')
                .margin({ bottom: 20 })
            }

            // 按钮区域
            if (this.showRetryButton || this.showCloseButton) {
              Row() {
                if (this.showCloseButton) {
                  // 关闭按钮
                  Button('关闭')
                    .width(this.showRetryButton ? '44%' : '100%')
                    .height(36)
                    .backgroundColor('#F5F5F5')
                    .fontColor('#666666')
                    .margin(this.showRetryButton ? { right: 12 } : {})
                    .onClick(() => {
                      this.onClose && this.onClose()
                    })
                }
                if (this.showRetryButton) {
                  // 重试按钮
                  Button('重试')
                    .width(this.showCloseButton ? '44%' : '100%')
                    .height(36)
                    .backgroundColor($r("app.color.brand_color"))
                    .fontColor(Color.White)
                    .onClick(() => {
                      this.onRetry && this.onRetry()
                    })
                }
              }
              .margin({ left: '7%', right: '7%', bottom: 8 })
            }
            // 设置网络改用贴底 ArcButton，不再在滚动内容里放一个纯文字按钮。
          }
          .alignItems(HorizontalAlign.Center)
          // 给底部 ArcButton 留出空间，长文案滚动时也不会被按钮盖住。
          .padding({ bottom: 76 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .width('100%')
        .borderRadius(12)
        .focusable(true)
        .focusOnTouch(true)
        .defaultFocus(true)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .transition(TransitionEffect.opacity(0).animation({ duration: 300 }))

      // ErrorPrompt 会盖在 13 个不同底色/模糊的页面上，取中性石墨而不是宿主 accent：
      // 它在任何深色背景上都可读，也不会和弹层里的「重试」抢主色。
      SettingsButton({
        arcBackgroundColor: ColorMetrics.rgba(47, 47, 54),
        arcFontColor: ColorMetrics.rgba(255, 255, 255),
        arcShadowColor: ColorMetrics.rgba(0, 0, 0, 0.4)
      })
      ArcScrollBar({ scroller: this.scroller })
    }.align(Alignment.Bottom)
  }
}

/**
 * 错误处理工具类
 */
interface GeneratedTypeLiteralInterface_1 {
  message: string;
  code: string;
}

export class ErrorHandler {
  /**
   * 获取错误信息和代码
   *
   * @param error 捕获的错误对象
   * @returns 包含消息和错误代码的对象
   */
  static getErrorDetails(error: Error): GeneratedTypeLiteralInterface_1 {
    if (error instanceof Error) {
      // 尝试从错误消息中提取错误代码
      const match = error.message.match(/\((\d+-\d+)\)/)
      const code = match ? match[1] : 'UNKNOWN'
      return {
        message: error.message,
        code: code
      }
    } else {
      return {
        message: String(error) || '发生未知错误',
        code: 'UNKNOWN'
      }
    }
  }
}



@ComponentV2
struct ContactDeveloperButton {
  @Param @Require pageInfos: NavPathStack | null
  @Param arcBackgroundColor?: ColorMetrics = undefined
  @Param arcFontColor?: ColorMetrics = undefined
  @Param arcShadowColor?: ColorMetrics = undefined

  build() {
    ArcButton({
      options: new ArcButtonOptions({
        label: "联系开发者",
        position: ArcButtonPosition.BOTTOM_EDGE,
        styleMode: this.arcBackgroundColor !== undefined ? ArcButtonStyleMode.CUSTOM : ArcButtonStyleMode.EMPHASIZED_LIGHT,
        backgroundColor: this.arcBackgroundColor,
        fontColor: this.arcFontColor,
        shadowColor: this.arcShadowColor,
        shadowEnabled: this.arcShadowColor !== undefined,
        onClick: () => {
          if (this.pageInfos !== null) {
            this.pageInfos.pushPathByName("CustomerServicePage", undefined)
          } else {
            this.getUIContext().getPromptAction().showToast({ message: "无法打开页面\n错误信息：导航堆栈未准备就绪" })
          }
        }
      })
    })
  }
}

// 背景不在这里：由 BiliHomeL1A/L1B 的 NavDestination 渐变（pageTopGradients.biliHome）透上来。
// 链路规则见 AGENTS.md「UI 背景色链路」。
// 首页推荐接口本身很少失败；加载不出来基本是设备网络问题，所以这里优先引导用户去联网。
@ComponentV2
export struct BiliLoadingErrorView0 {
  build() {
    Column() {
      Blank()
      Image($r("app.media.bili_loading_error_icon_teal"))
        .width("40%")
        .height("40%")
        .objectFit(ImageFit.Contain)
      Text("加载失败")
        .fontSize('17fp')
        .fontWeight(FontWeight.Bold)
        .fontColor('#EAF8FB')
      Blank()
      Text("网络问题，请将手表连接WiFi后再试试")
        .fontColor('#A7CBD3')
        .fontSize('13fp')
        .textAlign(TextAlign.Center)
        .width("85%")
      Blank()
      // 取自哔哩哔哩首页背景渐变（#406D77 → #18181A）里的青色主色：
      // 亮青底 + 深青黑字，阴影也带青色，避免默认蓝色 ArcButton 在这页跳色。
      SettingsButton({
        arcBackgroundColor: ColorMetrics.rgba(48, 175, 204),
        arcFontColor: ColorMetrics.rgba(6, 20, 26),
        arcShadowColor: ColorMetrics.rgba(48, 175, 204, 0.4)
      })
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 背景：BiliSearchList 根 Column 的 DarkTheme.background（#121212），不是搜索页品牌渐变。
// 链路规则见 AGENTS.md「UI 背景色链路」。
// 哔哩哔哩搜索页首屏失败：优先原地重试，其次联系开发者。
// 原来这里只有“联系开发者”，没有重试，等于把一次可能只是网络抖动的失败交给了人工。
@ComponentV2
export struct BiliLoadingErrorView1 {
  @Param @Require pageInfos: NavPathStack | null
  @Param errorMessage: string = '搜索加载失败，请检查网络后重试'
  @Param onRetry?: () => void = undefined

  private openCustomerService(): void {
    if (this.pageInfos !== null) {
      this.pageInfos.pushPathByName("CustomerServicePage", undefined)
    } else {
      this.getUIContext().getPromptAction().showToast({ message: "无法打开页面\n错误信息：导航堆栈未准备就绪" })
    }
  }

  build() {
    Column() {
      Blank()
      Image($r("app.media.bili_loading_error_icon_pink"))
        .width("30%")
        .height("30%")
        .objectFit(ImageFit.Contain)
      Text("加载失败")
        .fontSize('17fp')
        .fontWeight(FontWeight.Bold)
        .fontColor(DarkTheme.textPrimary)
      Text(this.errorMessage)
        .fontColor(DarkTheme.textSecondary)
        .fontSize('13fp')
        .textAlign(TextAlign.Center)
        .width("85%")
        .margin({ top: 6 })
      // 联系开发者是次要入口，放在正文下方；主操作留给贴底 ArcButton。
      Button('联系开发者')
        .height('24vp')
        .fontSize('12fp')
        .backgroundColor(Color.Transparent)
        .fontColor(DarkTheme.textSecondary)
        .onClick(() => this.openCustomerService())
      Blank()
      if (this.onRetry !== undefined) {
        ArcButton({
          options: new ArcButtonOptions({
            label: "重试",
            position: ArcButtonPosition.BOTTOM_EDGE,
            styleMode: ArcButtonStyleMode.CUSTOM,
            // 背景是 BiliSearchList 的 #121212；用哔哩哔哩粉和 pink 图标同色系，深色字保证对比度。
            backgroundColor: ColorMetrics.rgba(234, 122, 153),
            fontColor: ColorMetrics.rgba(42, 14, 18),
            pressedFontColor: ColorMetrics.rgba(42, 14, 18, 0.7),
            fontSize: LengthMetrics.fp(18),
            shadowEnabled: true,
            shadowColor: ColorMetrics.rgba(234, 122, 153, 0.4),
            onClick: () => {
              this.onRetry && this.onRetry()
            }
          })
        })
      }
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 背景：DouYinWebView 外层 Column 的 Color.Black（#000000），页面渐变在这里被不透明层切断。
// 链路规则见 AGENTS.md「UI 背景色链路」。
@ComponentV2
export struct DouYinLoadingErrorView0 {
  build() {
    Column() {
      Blank()
      Image($r("app.media.dou_videos_provider_loading_errror_icon"))
        .width("40%")
        .height("40%")
      Text("加载失败")
      Blank()
      Text("网络问题，请将手表连接WiFi后再试试")
        .fontColor($r("app.color.TextSecondaryColorInBlackBackground"))
        .width("90%")
      Blank()
      // 背景是 DouYinWebView 外层 Column 的黑色；用抖音红让主操作和页面品牌一致。
      SettingsButton({
        arcBackgroundColor: ColorMetrics.rgba(254, 44, 85),
        arcFontColor: ColorMetrics.rgba(255, 255, 255),
        arcShadowColor: ColorMetrics.rgba(254, 44, 85, 0.45)
      })
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}

// 背景：DouYinLoginPage 的 NavDestination 默认底色（#18181A），该页没有设置渐变。
// 链路规则见 AGENTS.md「UI 背景色链路」。
@ComponentV2
export struct DouYinLoadingErrorView1 {
  @Param @Require pageInfos: NavPathStack | null
  build() {
    Column() {
      Blank()
      Image($r("app.media.dou_logic_error_icon"))
        .width("40%")
        .height("40%")
      Text("加载失败")
      Blank()
      Text("逻辑错误，请联系腕上RSS开发者")
        .fontColor($r("app.color.TextSecondaryColorInBlackBackground"))
        .width("90%")
      Blank()
      ContactDeveloperButton({
        pageInfos:this.pageInfos,
        arcBackgroundColor: ColorMetrics.rgba(254, 44, 85),
        arcFontColor: ColorMetrics.rgba(255, 255, 255),
        arcShadowColor: ColorMetrics.rgba(254, 44, 85, 0.45)
      })
    }
    .justifyContent(FlexAlign.Center)
    .width("100%")
    .height("100%")
  }
}