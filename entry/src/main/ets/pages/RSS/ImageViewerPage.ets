/**
 * 图片查看器：独立的 NavDestination。
 *
 * 从阅读页进来时，这里不做普通的「页面推入」——导航转场由 common/ImageZoomTransition
 * 接管，本页背景是透明的，图片从阅读页里那张图的位置起飞、落到整屏居中 scaleToFit，
 * 同时整页从透明淡到不透明。两页的图在同一时刻、同一条轨迹上，所以看过去是一次
 * 连续的移动：背景从中途渐变成黑，图本身没有断点。
 *
 * 这里的图画在图片自己的绝对定位层里，不用 Stack 居中——居中会把「图居中的是容器」
 * 这件事交给布局，而交接需要的是「图居中于整屏」的精确矩形。
 */

import { image } from '@kit.ImageKit'
import { common } from '@kit.AbilityKit'
import { curves } from '@kit.ArkUI'
import { watchHeightVp, watchWidthVp } from '../../common/ScreenSize'
import {
  IMAGE_ZOOM,
  IMAGE_ZOOM_FLY_MS,
  IMAGE_ZOOM_STAGE_HEIGHT_VP,
  IMAGE_ZOOM_STAGE_WIDTH_VP,
  ImageZoomRect,
  ImageZoomStageImpl,
} from '../../common/ImageZoomTransition'
import { RemoteImage } from '../../common/rss/RemoteImage'
import { logTag } from '../../common/printLog'

/** 与阅读页正文图同一档解码宽度，命中共享内存缓存，切换时不重新解码。 */
const VIEWER_IMAGE_WIDTH_PX: number = 360;
/** 横向位移超过这么多 vp 算切图，否则关闭。 */
const VIEWER_SWIPE_SWITCH_VP: number = 40;

export interface ImageViewerPushData {
  srcs: string[]
  captions: string[]
  index: number
}

@Builder
export function ImageViewerPageBuilder(_name: string, param: Object) {
  ImageViewerPage({
    srcs: (param as ImageViewerPushData).srcs,
    captions: (param as ImageViewerPushData).captions,
    startIndex: (param as ImageViewerPushData).index,
  })
}

@ComponentV2
export struct ImageViewerPage {
  @Param @Require srcs: string[]
  @Param @Require captions: string[]
  @Param @Require startIndex: number

  // 整页透明度：0 = 完全透明，能看见下面还在飞的阅读页那张图
  @Local private pageOpacity: number = 0
  @Local private imageX: number = 0
  @Local private imageY: number = 0
  @Local private imageWidth: number = 0
  @Local private imageHeight: number = 0
  @Local private imageRadius: number = 8
  @Local private pixelMap: image.PixelMap | null = null
  @Local private currentIndex: number = 0
  @Local private caption: string = ''

  private pageInfos: NavPathStack | null = null
  private remoteImages: RemoteImage | null = null
  private disposed: boolean = false

  aboutToAppear(): void {
    this.currentIndex = this.clampIndex(this.startIndex)
    const context = this.getUIContext().getHostContext()
    this.remoteImages = new RemoteImage(context as common.UIAbilityContext)
    this.caption = this.captionAt(this.currentIndex)

    // 首帧必须精确贴住阅读页里那张图：位置、尺寸、圆角、底色全部对齐，
    // 否则交接那一帧会露出两套几何之间的缝。
    const origin: ImageZoomRect = IMAGE_ZOOM.origin
    this.pixelMap = IMAGE_ZOOM.pixelMap
    this.imageX = origin.x
    this.imageY = origin.y
    this.imageWidth = origin.width
    this.imageHeight = origin.height
    this.imageRadius = 8
    this.pageOpacity = 0

    IMAGE_ZOOM.attachViewer(new ImageZoomStageImpl(
      (): void => {
        this.snapToOrigin()
      },
      (): void => {
        this.flyToTarget()
      },
      (): void => {
      },
    ))

    if (this.pixelMap === null) {
      // 没有交接数据（直接 push 进来，或解码结果丢了）：自己加载并直接落到查看器姿态
      this.loadCurrent()
    } else {
      // 兜底：万一发令没到（交接被打断），不能让整页停在透明状态吃点击
      setTimeout(() => {
        if (!this.disposed && this.pageOpacity === 0) {
          console.warn(logTag, 'imageViewer 未收到起飞指令，直接落位')
          this.flyToTarget()
        }
      }, 1200)
    }
  }

  aboutToDisappear(): void {
    this.disposed = true
    // 交接还没放行就离开：必须把导航转场结束掉，否则栈会一直停在「转场中」
    if (IMAGE_ZOOM.active) {
      IMAGE_ZOOM.reset()
    }
    if (this.remoteImages !== null) {
      this.remoteImages.cancel()
    }
  }

  private clampIndex(index: number): number {
    if (this.srcs.length === 0) {
      return 0
    }
    return Math.max(0, Math.min(index, this.srcs.length - 1))
  }

  private captionAt(index: number): string {
    return index >= 0 && index < this.captions.length ? this.captions[index] : ''
  }

  private snapToOrigin(): void {
    const origin: ImageZoomRect = IMAGE_ZOOM.origin
    this.imageX = origin.x
    this.imageY = origin.y
    this.imageWidth = origin.width
    this.imageHeight = origin.height
    this.imageRadius = 8
    this.pageOpacity = 0
  }

  /** 由 ImageZoomTransition 发令：与阅读页同一时刻起飞。 */
  private flyToTarget(): void {
    const target: ImageZoomRect = IMAGE_ZOOM.target
    this.imageX = target.x
    this.imageY = target.y
    this.imageWidth = target.width
    this.imageHeight = target.height
    this.imageRadius = 0
    // 背景跟着一起淡入：文章页到黑场的过渡就是这一步，不是硬切
    this.pageOpacity = 1
  }

  /** 没有交接数据时的兜底：自己加载当前图，直接落到查看器姿态（不飞）。 */
  private loadCurrent(): void {
    const images = this.remoteImages
    const src = this.srcs[this.currentIndex]
    if (images === null || src === undefined || src.length === 0) {
      return
    }
    images.load(src, VIEWER_IMAGE_WIDTH_PX).then((result) => {
      if (this.disposed || !result.ok || result.pixelMap === null) {
        console.warn(logTag, 'imageViewer 加载失败 url=' + src + ' 原因=' + result.reason)
        return
      }
      this.applyCentered(result.pixelMap, result.width, result.height)
      this.pageOpacity = 1
    })
  }

  /** 把一张已解码的图按整屏居中 scaleToFit 摆好。 */
  private applyCentered(pixelMap: image.PixelMap, widthPx: number, heightPx: number): void {
    const rect = this.centerRect(this.getUIContext().px2vp(widthPx),
      this.getUIContext().px2vp(heightPx))
    this.pixelMap = pixelMap
    this.imageX = rect.x
    this.imageY = rect.y
    this.imageWidth = rect.width
    this.imageHeight = rect.height
    this.imageRadius = 0
  }

  /** 整屏居中 + scaleToFit：切换图片后重新按新图的比例算一次。 */
  private centerRect(widthVp: number, heightVp: number): ImageZoomRect {
    const safeWidth = Math.max(1, widthVp)
    const safeHeight = Math.max(1, heightVp)
    const scale = Math.min(IMAGE_ZOOM_STAGE_WIDTH_VP / safeWidth,
      IMAGE_ZOOM_STAGE_HEIGHT_VP / safeHeight)
    const width = safeWidth * scale
    const height = safeHeight * scale
    return {
      x: (watchWidthVp - width) / 2,
      y: (watchHeightVp - height) / 2,
      width: width,
      height: height,
    }
  }

  private close(reason: string): void {
    // 交接还没结束就关，会把导航转场挂在半路
    if (IMAGE_ZOOM.active) {
      return
    }
    console.info(logTag, 'imageViewer close reason=' + reason)
    if (this.pageInfos !== null) {
      this.pageInfos.pop()
    }
  }

  private showImage(index: number): void {
    const next = this.clampIndex(index)
    if (next === this.currentIndex) {
      return
    }
    this.currentIndex = next
    this.caption = this.captionAt(next)
    const src = this.srcs[next]
    const images = this.remoteImages
    if (images === null || src.length === 0) {
      return
    }
    images.load(src, VIEWER_IMAGE_WIDTH_PX).then((result) => {
      if (this.disposed || !result.ok || result.pixelMap === null) {
        console.warn(logTag, 'imageViewer 切换失败 url=' + src + ' 原因=' + result.reason)
        return
      }
      // 切换后仍按新图比例重新居中，位置不会跳
      this.applyCentered(result.pixelMap, result.width, result.height)
    })
  }

  private switchImage(delta: number): void {
    const total = this.srcs.length
    if (total <= 1) {
      this.close('swipe-single')
      return
    }
    this.showImage((this.currentIndex + delta + total) % total)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)

        if (this.pixelMap !== null) {
          Image(this.pixelMap)
            .objectFit(ImageFit.Contain)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .position({ x: this.imageX, y: this.imageY })
            .borderRadius(this.imageRadius)
            .backgroundColor('#000000')
            // 与阅读页那张图同一条曲线、同一个时长，中途才叠得住
            .animation({ duration: IMAGE_ZOOM_FLY_MS, curve: curves.springCurve(0, 1, 200, 20) })
        }

        Column({ space: 4 }) {
          if (this.caption.length > 0) {
            Text(this.caption)
              .fontSize(9)
              .fontColor('#C8C8C8')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .padding({ left: 10, right: 10 })
          }
          Text('点击关闭 · 左右滑动切换')
            .fontSize(9)
            .fontColor(Color.White)
            .textShadow({ radius: 4, color: '#99000000', offsetX: 0, offsetY: 1 })
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#8C000000')
            .borderRadius(12)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 10 })
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .opacity(this.pageOpacity)
      // 与阅读页那张图的淡出同一条曲线：互补之后亮度才守恒，中间不会暗一下
      .animation({ duration: IMAGE_ZOOM_FLY_MS, curve: Curve.EaseInOut })
      .onClick(() => {
        this.close('tap');
      })
      // 全方向识别：略微斜的点击也要走到关闭分支，不能被只认横向的手势吞掉
      .gesture(PanGesture({ direction: PanDirection.All })
        .onActionEnd((event: GestureEvent) => {
          const offsetX = (event as PanGestureEvent).offsetX;
          if (offsetX <= -VIEWER_SWIPE_SWITCH_VP) {
            this.switchImage(1);
          } else if (offsetX >= VIEWER_SWIPE_SWITCH_VP) {
            this.switchImage(-1);
          } else {
            this.close('pan-small');
          }
        }))
    }
    .hideTitleBar(true)
    // 页面本身不能有底色：底色会把下面的阅读页整块盖住，交叉溶解就没了
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      this.pageInfos = context.pathStack
    })
  }
}
