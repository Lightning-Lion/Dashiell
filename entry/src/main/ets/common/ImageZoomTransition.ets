/**
 * 阅读页图片 → 图片查看器 的跨页交接（一镜到底 + 交叉溶解）。
 *
 * 为什么必须跨页：查看器是独立的 NavDestination（要能返回、能左右切图），图片得在两个
 * 页面之间交接。直接 push 会跑系统推入动画，看着像图从新页面里「钻」出来；路径上要是
 * 压着按钮或悬浮窗，更是硬穿透。
 *
 * 做法是两段同轨迹的移动 + 透明度交叉：
 *   阅读页在顶层 overlay 里把图从正文位置送到「整屏居中 scaleToFit」的落点；
 *   查看器里另有一份同样的图，从同一个起点、在同一时刻起飞，走同一条轨迹。
 *   两边位置全程严格重合，所以交叉溶解期间两帧像素相同，混合后亮度不变 ——
 *   看不到重影，只看到背景从文章渐变成黑。
 *
 * 「同一时刻」是这里的核心难点：push 到目标页首帧的耗时不固定，谁先动都会错位。
 * 所以两边都不许自己起飞，统一等 proxy（= 目标页已就绪）后由 startFlight() 发令。
 *
 * 数值全住在各自页面里（阅读页的飞行层、查看器的入场层），这里只传几何和时序：
 * 跨组件改 @Trace 只让布局跳到新值、不插值，这条在 RSSHeroTransition 里已验证过。
 */

import { image } from '@kit.ImageKit'
import { Task } from './sleep'
import { logTag } from './printLog'

/** 相对窗口左上角的矩形（vp）。 */
export interface ImageZoomRect {
  x: number
  y: number
  width: number
  height: number
}

/** 落点可用区：与查看器里图片的封顶值同一组，落地即对齐。 */
export const IMAGE_ZOOM_STAGE_WIDTH_VP: number = 210
export const IMAGE_ZOOM_STAGE_HEIGHT_VP: number = 188
/** 飞行时长。两边必须用同一个数字，否则中途叠不上。 */
export const IMAGE_ZOOM_FLY_MS: number = 260
/** 等 proxy 的上限；拿不到就照常起飞，不把交互卡住。 */
const PROXY_TIMEOUT_MS: number = 500
/** 等目标页首帧落位。起飞指令发出去时它还没上屏的话，那段动画会被吞掉。 */
const VIEWER_SETTLE_MS: number = 32

/** 两端各实现一份，方法内部改自己的 @Local，交给 .animation() 插值。 */
export interface ImageZoomStage {
  /** 首帧贴到 origin，无动画。 */
  snapToOrigin(): void
  /** 开始飞行：从当前姿态插值到 target。 */
  flyToTarget(): void
  /** 交接结束，收起自己这一层。 */
  finish(): void
}

/** 用回调把 struct 包一层：struct 的 this 只出现在箭头函数里，不越过组件边界。 */
export class ImageZoomStageImpl implements ImageZoomStage {
  private onSnap: () => void
  private onFly: () => void
  private onFinish: () => void

  constructor(onSnap: () => void, onFly: () => void, onFinish: () => void) {
    this.onSnap = onSnap
    this.onFly = onFly
    this.onFinish = onFinish
  }

  snapToOrigin(): void {
    this.onSnap()
  }

  flyToTarget(): void {
    this.onFly()
  }

  finish(): void {
    this.onFinish()
  }
}

export interface ImageZoomOptions {
  src: string
  caption: string
  /** 已经解码好的图：交接第一帧就要显示它，不能等查看器再 load。 */
  pixelMap: image.PixelMap
  /** 图片在阅读页里的位置（窗口坐标）。 */
  origin: ImageZoomRect
  /** 整屏居中 scaleToFit 的落点（窗口坐标）。 */
  target: ImageZoomRect
}

export class ImageZoomTransition {
  /** 转场进行中：转场工厂靠它判断这次 push 要不要接管。 */
  active: boolean = false
  src: string = ''
  caption: string = ''
  pixelMap: image.PixelMap | null = null
  origin: ImageZoomRect = { x: 0, y: 0, width: 0, height: 0 }
  target: ImageZoomRect = { x: 0, y: 0, width: 0, height: 0 }

  private reader: ImageZoomStage | null = null
  private viewer: ImageZoomStage | null = null
  // 发令标志：查看器可能在指令之后才挂上，用它在 attach 时补发一次
  private flightStarted: boolean = false
  private generation: number = 0

  // customNavContentTransition 交过来的 proxy：拿到它就说明这次 push 不跑系统动画、
  // 目标页已经直接落位。用完必须 finishTransition，否则导航栈会一直停在「转场中」。
  private proxy: NavigationTransitionProxy | null = null
  private proxyWaiter: (() => void) | null = null

  attachReader(stage: ImageZoomStage): void {
    this.reader = stage
  }

  /** 查看器在 aboutToAppear 里挂上；如果指令已经发过，立刻补飞，别让它停在起点。 */
  attachViewer(stage: ImageZoomStage): void {
    this.viewer = stage
    if (this.flightStarted) {
      stage.flyToTarget()
    }
  }

  /** 阅读页点击时调用：只记录几何并让阅读页贴到起点，push 交给调用方紧接着做。 */
  begin(options: ImageZoomOptions): void {
    this.src = options.src
    this.caption = options.caption
    this.pixelMap = options.pixelMap
    this.origin = options.origin
    this.target = options.target
    this.generation++
    this.flightStarted = false
    this.active = true
    this.reader?.snapToOrigin()
  }

  attachProxy(proxy: NavigationTransitionProxy): void {
    if (!this.active) {
      // 迟到的旧转场：立刻放行，别把导航栈挂住
      try {
        proxy.finishTransition()
      } catch (error) {
        console.warn(logTag, 'imageZoom 释放迟到 proxy 失败：' + String(error))
      }
      return
    }
    this.proxy = proxy
    const waiter = this.proxyWaiter
    this.proxyWaiter = null
    if (waiter !== null) {
      waiter()
    }
  }

  private whenProxyReady(timeoutMs: number): Promise<void> {
    if (this.proxy !== null) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      let done: boolean = false
      const finish = (): void => {
        if (done) {
          return
        }
        done = true
        this.proxyWaiter = null
        resolve()
      }
      this.proxyWaiter = finish
      setTimeout(finish, timeoutMs)
    })
  }

  /**
   * 阅读页 push 之后调用：
   *   等目标页就绪 → 同帧发令两边起飞（位置与透明度一起走）→ 放行导航转场。
   */
  async run(): Promise<void> {
    if (!this.active) {
      return
    }
    const generation = this.generation
    try {
      await this.whenProxyReady(PROXY_TIMEOUT_MS)
      if (generation !== this.generation) {
        return
      }
      // 让查看器先按 origin 出一帧，否则它那侧的动画起点还没落位
      await Task.sleep(VIEWER_SETTLE_MS / 1000)
      if (generation !== this.generation) {
        return
      }
      this.startFlight()
      // 多留一点余量：清理阅读页那层图必须晚于查看器 opacity 走到 1，
      // 早一帧就会露出下面还没被盖住的文章。
      await Task.sleep((IMAGE_ZOOM_FLY_MS + 32) / 1000)
      if (generation !== this.generation) {
        return
      }
    } finally {
      if (generation === this.generation) {
        this.finish()
      }
    }
  }

  private startFlight(): void {
    if (this.flightStarted) {
      return
    }
    this.flightStarted = true
    console.debug(logTag, 'imageZoom 起飞 src=' + this.src)
    this.reader?.flyToTarget()
    const viewer = this.viewer
    if (viewer !== null) {
      viewer.flyToTarget()
    }
  }

  /** 结束这次自定义导航转场（可重复调用，第二次无操作）。 */
  finish(): void {
    this.active = false
    this.flightStarted = false
    // reader 是常驻的飞行层（挂在 Navigation 外层），不能在这里摘掉：
    // 下一次点图还要靠它。viewer 是目标页，返回后就销毁了，必须清。
    const reader = this.reader
    this.viewer = null
    if (reader !== null) {
      reader.finish()
    }
    const proxy = this.proxy
    this.proxy = null
    if (proxy !== null) {
      try {
        proxy.finishTransition()
      } catch (error) {
        console.warn(logTag, 'imageZoom finishTransition 失败：' + String(error))
      }
    }
  }

  /** 被中断 / 异常路径也要复位，不能把 active 和 proxy 留在半路。 */
  reset(): void {
    this.generation++
    this.src = ''
    this.caption = ''
    this.pixelMap = null
    const waiter = this.proxyWaiter
    this.proxyWaiter = null
    if (waiter !== null) {
      waiter()
    }
    this.finish()
  }

  handleTransitionEnd(success: boolean): void {
    if (!success && this.active) {
      console.warn(logTag, 'imageZoom 导航转场被中断，强制复位')
      this.reset()
    }
  }
}

export const IMAGE_ZOOM: ImageZoomTransition = new ImageZoomTransition()

/**
 * 给 Navigation.customNavContentTransition 用的转场工厂。
 *
 * 只在「图片交接正在进行 + 这次是 push」时接管：返回的 transition 不改任何页面属性，
 * 只把 proxy 交给 ImageZoomTransition；飞行结束后由它调 proxy.finishTransition()。
 * 其它跳转（含返回）返回 undefined，交回系统默认转场。
 */
export function imageZoomNavTransition(
  from: NavContentInfo,
  to: NavContentInfo,
  operation: NavigationOperation,
  zoom: ImageZoomTransition,
): NavigationAnimatedTransition | undefined {
  if (operation !== NavigationOperation.PUSH || !zoom.active) {
    return undefined
  }
  console.debug(logTag, 'imageZoom 接管导航转场 from=' + from.name + ' to=' + to.name)
  return {
    // 覆盖「push → 等 proxy → 飞行」的最坏路径，正常 300ms 内结束
    timeout: 2000,
    onTransitionEnd: (success: boolean): void => {
      zoom.handleTransitionEnd(success)
    },
    transition: (proxy: NavigationTransitionProxy): void => {
      zoom.attachProxy(proxy)
    },
  }
}
