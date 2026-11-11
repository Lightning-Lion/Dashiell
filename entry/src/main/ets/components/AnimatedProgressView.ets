import { DarkTheme } from '../common/Theme';

@ComponentV2
export struct AnimatedProgressView {
  // 转圈的颜色。图标是矢量图，fillColor 能盖掉它自带的填充色。
  // 默认取 App 品牌色；各模块按自己的色相传入（见 DarkTheme.accents）。
  @Param color: ResourceColor = DarkTheme.primary

  build() {
    Image($r('app.media.loading_icon'))
      // 确保即使主线程阻塞，加载图标仍然在屏
      .syncLoad(true)
      .objectFit(ImageFit.Contain)
      .alt('加载图标')
      .fillColor(this.color)
      // 不受主线程阻塞的旋转动画
      .transition(TransitionEffect.rotate({
        angle:-15458
        // 最多旋转60秒
      }).animation({ duration:60000,curve: Curve.Linear }))
      .width("100%")
      .height("100%")
  }
}
