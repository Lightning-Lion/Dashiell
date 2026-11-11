import { applyDirectEntry } from '../../common/dev/DirectEntry'
import { LandingPageL1 } from "../LandingPage/LandingPage"
import { RSSHeroTransition, rssHeroNavTransition } from '../../common/RSSHeroTransition'
import { RSSHeroTransitionOverlay } from '../../components/RSSHeroTransitionOverlay'
import { IMAGE_ZOOM, imageZoomNavTransition } from '../../common/ImageZoomTransition'
import { ImageZoomTransitionOverlay } from '../../components/ImageZoomTransitionOverlay'

@ComponentV2
export struct NavigationStack {
  @Local pageInfos: NavPathStack = new NavPathStack()
  // 首页条目点进去的一镜到底 + 交叉渐变转场。Overlay 必须与 Navigation 同级、且在它之后，
  // 否则推入的 NavDestination 会盖住 hero；推页本身由 customNavContentTransition 接管，
  // 目标页不跑系统动画、直接落位，hero 淡出时就是交叉渐变。
  @Local private hero: RSSHeroTransition = new RSSHeroTransition()
  aboutToAppear(): void {
    if (this.pageInfos.size() !== 0) { return; }
    applyDirectEntry(this.pageInfos)
  }
  build() {
    Stack() {
      Navigation(this.pageInfos) {
        LandingPageL1({ pageInfos: this.pageInfos, hero: this.hero })
      }
      .hideTitleBar(true)
      // 只接管两种 push：首页 hero 的一镜到底，和阅读页 → 图片查看器的图片交接。
      // 其它跳转（含所有返回）返回 undefined，交回系统默认转场。
      .customNavContentTransition((from: NavContentInfo, to: NavContentInfo,
        operation: NavigationOperation): NavigationAnimatedTransition | undefined => {
        // 图片交接优先：它只在交接进行中才认领，平时拿不到
        const imageZoom = imageZoomNavTransition(from, to, operation, IMAGE_ZOOM)
        if (imageZoom !== undefined) {
          return imageZoom
        }
        return rssHeroNavTransition(from, to, operation, this.hero)
      })

      RSSHeroTransitionOverlay({ hero: this.hero })
      // 图片跨页交接的飞行层：同样必须在这里，push 出去的 NavDestination 盖不住它
      ImageZoomTransitionOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
