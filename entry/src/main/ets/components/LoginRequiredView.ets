import {
  ArcButton,
  ArcButtonOptions,
  ArcButtonPosition,
  ArcButtonStyleMode,
  ColorMetrics,
  LengthMetrics
} from '@kit.ArkUI';
import { DarkTheme } from '../common/Theme';

/**
 * 登录中间页的视觉风格。只影响配色和背景，不影响“继续”要打开哪个登录页。
 */
export enum LoginRequiredVisual {
  Bili = 0,
  Douyin = 1
}

/**
 * 需要登录才能使用的功能，统一先插入一个 NavDestination 中间页。
 * “继续”是画面主按钮（ArcButton，贴底）；“取消”是它上方的小号非强调按钮。
 *
 * 这一层只负责视觉与两个按钮的回调，登录页跳转和登录后的回退由各账号的路由包装页处理：
 * - pages/BiliLogin/BiliLoginRequiredPage.ets
 * - pages/DouYin/DouYinLoginRequiredPage.ets
 */
@ComponentV2
export struct LoginRequiredView {
  @Param @Require featureName: string
  @Param @Require accountName: string
  @Param visual: LoginRequiredVisual = LoginRequiredVisual.Bili
  @Param @Require onContinue: () => void
  @Param onCancel: () => void = () => {
  }

  private gradientColors(): Array<[ResourceColor, number]> {
    return this.visual === LoginRequiredVisual.Douyin ?
      DarkTheme.pageTopGradients.douyin : DarkTheme.pageTopGradients.brand;
  }

  private isDouyin(): boolean {
    return this.visual === LoginRequiredVisual.Douyin;
  }

  private arcBackground(): ColorMetrics {
    return this.isDouyin() ?
      ColorMetrics.rgba(254, 44, 85) : ColorMetrics.rgba(227, 135, 147);
  }

  private arcFontColor(): ColorMetrics {
    return this.isDouyin() ?
      ColorMetrics.rgba(255, 255, 255) : ColorMetrics.rgba(42, 14, 18);
  }

  private arcPressedFontColor(): ColorMetrics {
    return this.isDouyin() ?
      ColorMetrics.rgba(255, 255, 255, 0.7) : ColorMetrics.rgba(42, 14, 18, 0.7);
  }

  private arcShadowColor(): ColorMetrics {
    return this.isDouyin() ?
      ColorMetrics.rgba(254, 44, 85, 0.45) : ColorMetrics.rgba(227, 135, 147, 0.4);
  }

  build() {
    Column() {
      Blank()
      Text(`${this.featureName}功能需登录${this.accountName}账号后使用`)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(DarkTheme.textPrimary)
        .textAlign(TextAlign.Center)
        .lineBreakStrategy(LineBreakStrategy.GREEDY)
        .width('86%')
      Blank()
      Button('取消', { type: ButtonType.Normal })
        .fontSize(13)
        .fontColor(DarkTheme.textSecondary)
        .backgroundColor(Color.Transparent)
        .height(30)
        // 和底部 ArcButton 拉开距离，避免两个按钮贴在一起。
        .margin({ bottom: 24 })
        .onClick(() => this.onCancel())
      // 显式使用对应账号的 surface palette，不依赖 ArcButton 的默认系统蓝。
      ArcButton({
        options: new ArcButtonOptions({
          label: "继续",
          position: ArcButtonPosition.BOTTOM_EDGE,
          styleMode: ArcButtonStyleMode.CUSTOM,
          backgroundColor: this.arcBackground(),
          fontColor: this.arcFontColor(),
          pressedFontColor: this.arcPressedFontColor(),
          fontSize: LengthMetrics.fp(18),
          shadowEnabled: true,
          shadowColor: this.arcShadowColor(),
          onClick: () => this.onContinue()
        })
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .linearGradient({ colors: this.gradientColors() })
  }
}
