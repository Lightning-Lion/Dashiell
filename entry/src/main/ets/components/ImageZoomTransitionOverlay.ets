// 图片跨页交接的飞行层。
//
// 必须挂在 Navigation 的兄弟层、且在它之后：推入的 NavDestination 会盖住 Navigation
// 子树里的东西，飞行层要是画在阅读页内部，push 之后就未必还参与绘制了；挂在这里则
// 永远在最上面，交接途中路上有什么按钮、注释、悬浮窗都挡不住它。
// RSSHeroTransitionOverlay 也是同一条结论：飞行层挂在 Navigation 外面才不被盖住。
//
// 只负责「把图从阅读页的位置送到整屏居中」这一件事；背景变黑、图片接管都由
// ImageViewerPage 自己做，两边共用 IMAGE_ZOOM 里的几何与时长常量。

import { image } from '@kit.ImageKit'
import { curves } from '@kit.ArkUI'
import {
  IMAGE_ZOOM,
  IMAGE_ZOOM_FLY_MS,
  ImageZoomRect,
  ImageZoomStageImpl,
} from '../common/ImageZoomTransition'

@ComponentV2
export struct ImageZoomTransitionOverlay {
  @Local private showing: boolean = false
  @Local private pixelMap: image.PixelMap | null = null
  @Local private x: number = 0
  @Local private y: number = 0
  // 不能叫 width/height：它们是 CustomComponent 的内置属性方法，同名会编译失败
  @Local private boxWidth: number = 0
  @Local private boxHeight: number = 0
  @Local private radius: number = 0

  aboutToAppear(): void {
    // 常驻组件，登记一次即可；点图时 stage 一定已经就位
    IMAGE_ZOOM.attachReader(new ImageZoomStageImpl(
      (): void => {
        this.snapToOrigin()
      },
      (): void => {
        this.flyToTarget()
      },
      (): void => {
        this.hide()
      },
    ))
  }

  /** 首帧贴住阅读页里那张图；此时节点刚创建，几何必须已经就位。 */
  private snapToOrigin(): void {
    const origin: ImageZoomRect = IMAGE_ZOOM.origin
    this.pixelMap = IMAGE_ZOOM.pixelMap
    this.x = origin.x
    this.y = origin.y
    this.boxWidth = origin.width
    this.boxHeight = origin.height
    this.radius = 8
    this.showing = this.pixelMap !== null
  }

  /** 与查看器同拍起飞；这里不淡出，覆盖交给查看器的整页渐入。 */
  private flyToTarget(): void {
    const target: ImageZoomRect = IMAGE_ZOOM.target
    this.x = target.x
    this.y = target.y
    this.boxWidth = target.width
    this.boxHeight = target.height
    this.radius = 0
  }

  private hide(): void {
    this.showing = false
    this.pixelMap = null
  }

  build() {
    if (this.showing && this.pixelMap !== null) {
      Stack() {
        Image(this.pixelMap)
          .objectFit(ImageFit.Contain)
          .width(this.boxWidth)
          .height(this.boxHeight)
          .position({ x: this.x, y: this.y })
          .borderRadius(this.radius)
          .backgroundColor('#1E1E1E')
          // 与查看器里那张图同一个时长、同一条曲线：中途叠不上就会看见两张图
          .animation({ duration: IMAGE_ZOOM_FLY_MS, curve: curves.springCurve(0, 1, 200, 20) })
      }
      .width('100%')
      .height('100%')
      // 交接期间吞掉点击，避免连点同一张图 / 误触查看器的关闭
      .hitTestBehavior(HitTestMode.Block)
    }
  }
}
