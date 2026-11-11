// 首页 RSS 列表条目点进去时的「一镜到底 + 交叉渐变」转场。
//
// 整个扩展过程都停在首页里（导航栈不动，只在这页之上盖一层 hero）；
// 扩展完成后用 customNavContentTransition 接管这次推页：目标页不跑系统推入动画，
// 直接落在 hero 下面，然后 hero 淡出——两张画面在同一位置交叉渐变，中间不再经过纯黑。
//
// 层叠关系：
//   Index(233fp)
//     └─ NavigationStack
//          ├─ Navigation(NavBar = HomePageRSSList, NavDestination = 目标页)
//          └─ RSSHeroTransitionOverlay   ← 必须在这里，才能盖住推入后的 NavDestination
//
// 分工：
//   这里负责「时序 + 几何计算 + 导航转场握手」；
//   真正参与动画的数值全部是 Overlay 自己的 @Local（见 components/RSSHeroTransitionOverlay.ets）。
//
// 为什么不在这个对象里放 x/width/opacity 再 animateTo：
//   @ObservedV2 的 @Trace 字段被另一个组件读取时，改它只会让布局跳到新值，
//   动画不会生效（animateTo 的作用域只覆盖「渲染它的组件」自己的状态变化）。
//   所以状态必须住在渲染它的 Overlay 里，由 Overlay 自己 animateTo。
//
// 设计要点：被点卡片先在同页内弹性扩展成全屏，再由 customNavContentTransition 接管这次推页。

import { logTag } from './printLog'
import { Task } from './sleep'
import { watchHeightFp, watchWidthFp } from './ScreenSize'

export interface HeroOrigin {
  x: number
  y: number
  width: number
  height: number
}

export interface HeroGeometry {
  x: number
  y: number
  width: number
  height: number
  radius: number
  iconSize: number
  iconX: number
  iconY: number
  textX: number
  textY: number
  textWidth: number
  fontSize: number
}

/** 由 RSSHeroTransitionOverlay 实现：这些方法内部用 Overlay 自己的 @Local + .animation()。 */
export interface HeroStage {
  snap(geometry: HeroGeometry, contentVisible: boolean): void
  expandTo(target: HeroGeometry): void
  fadeSurface(target: number): void
}

export interface HeroBeginOptions {
  title: string
  // 点击时量到的卡片矩形（窗口坐标）。量不到就不展开，只做整屏 hero 的交叉渐变。
  origin: HeroOrigin | null
  // 扩展完成后再执行的真正推页；由 customNavContentTransition 接住，目标页直接落位。
  commit: () => Promise<boolean>
}

// 时间常量（毫秒）。想整体变快/变慢只改这里。
// 动画时长同时被 Overlay 的 .animation() 使用，所以导出。
export const HERO_EXPAND_MS: number = 420
export const HERO_CROSSFADE_MS: number = 260
const EXPAND_HOLD_MS: number = 100 // 全屏停留，让「上图下文」被看清
// 推页完成后先让目标页出一两帧，再开始褪 hero，避免淡出的第一帧露出背后的首页
const HANDOFF_DELAY_MS: number = 48
// 自定义转场没接上时的兜底等待：等系统默认推入动画落定再交叉渐变
const FALLBACK_PUSH_MS: number = 200
// 等 customNavContentTransition 把 proxy 交过来的最长时间。
// proxy 同时也是「目标页已经就绪」的信号（慢页面可能隔几秒才交给过来），
// 这段时间 hero 一直保持整屏，所以宁可等久一点也不要提前淡出露出首页。
const NAV_PROXY_TIMEOUT_MS: number = 4000
const WAITING_DELAY_MS: number = 400
// 看门狗要晚于「等 proxy + 交叉渐变」的最坏路径
const WATCHDOG_MS: number = 8000
const WAIT_READY_TIMEOUT_MS: number = 300 // hero 上屏的最长等待

// 展开后的布局：落在圆屏内接安全区内，图标在上、文字在下。
const RADIUS_START: number = 16 // 与列表卡片一致
const ICON_START_SIZE: number = 32
const ICON_START_X: number = 16 // 卡片内 start padding
const ICON_END_SIZE: number = 64
const ICON_END_Y: number = 66
const TEXT_START_X: number = 61 // 16 padding + 32 图标 + 13 间距
const TEXT_START_FONT_SIZE: number = 16
const TEXT_END_FONT_SIZE: number = 20
const TEXT_END_WIDTH: number = 150
const TEXT_END_Y: number = 140

@ObservedV2
export class RSSHeroTransition {
  // 只有「开关类」状态放在这里：它们不需要动画
  @Trace active: boolean = false
  @Trace title: string = ''
  @Trace waiting: boolean = false

  private stage: HeroStage | null = null
  private running: boolean = false
  private commit: (() => Promise<boolean>) | null = null
  private watchdogId: number = -1
  // 看门狗强制复位后，让还在 sleep 里的旧流程自己退出
  private generation: number = 0
  // hero 是否已经真正上屏（等 onAppear 再开始展开，否则动画会丢）
  private stageReady: boolean = false
  private readyResolve: (() => void) | null = null
  // customNavContentTransition 交过来的 proxy：拿到它就说明这次推页不会跑系统动画，
  // 目标页已经直接落位，可以开始交叉渐变；用完必须 finishTransition 才能结束导航转场。
  private navigationProxy: NavigationTransitionProxy | null = null
  private navigationProxyWaiter: ((proxy: NavigationTransitionProxy | null) => void) | null = null

  /** Overlay 在 aboutToAppear 里登记自己；Overlay 常驻，所以点条目时 stage 一定已经就位。 */
  attachStage(stage: HeroStage): void {
    this.stage = stage
  }

  /** Overlay 里 hero 的 onAppear 回调：确认节点已经上屏。 */
  notifyStageReady(): void {
    this.stageReady = true
    const resolve = this.readyResolve
    if (resolve !== null) {
      this.readyResolve = null
      resolve()
    }
  }

  /** 等到 hero 真的上屏（或超时）。在节点还没上屏时改属性，动画会整个丢掉。 */
  private waitStageReady(timeoutMs: number): Promise<void> {
    if (this.stageReady) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve) => {
      let done: boolean = false
      const finish = (): void => {
        if (done) {
          return
        }
        done = true
        this.readyResolve = null
        resolve()
      }
      this.readyResolve = finish
      setTimeout(finish, timeoutMs)
    })
  }

  /**
   * 由 Navigation.customNavContentTransition 调用：这次 hero 推页的 proxy 交进来。
   *
   * 只要拿到 proxy，系统就不会给这次 push 跑默认推入动画；目标页会直接落位在 hero 下面，
   * 随后把 hero 淡出，视觉上就是「整屏 hero → 目标页」的交叉渐变。
   */
  attachNavigationProxy(proxy: NavigationTransitionProxy): void {
    if (!this.running) {
      // 迟到的旧转场：立刻放行，避免导航栈被挂在那边
      proxy.finishTransition()
      return
    }
    this.navigationProxy = proxy
    const waiter = this.navigationProxyWaiter
    this.navigationProxyWaiter = null
    if (waiter !== null) {
      waiter(proxy)
    }
  }

  /** 等 proxy 交过来；自定义转场没触发（例如系统不支持根页面）时超时返回 null。 */
  private waitNavigationProxy(timeoutMs: number): Promise<NavigationTransitionProxy | null> {
    const current = this.navigationProxy
    if (current !== null) {
      return Promise.resolve(current)
    }
    return new Promise<NavigationTransitionProxy | null>((resolve) => {
      let done: boolean = false
      const finish = (proxy: NavigationTransitionProxy | null): void => {
        if (done) {
          return
        }
        done = true
        this.navigationProxyWaiter = null
        resolve(proxy)
      }
      this.navigationProxyWaiter = finish
      setTimeout(() => finish(this.navigationProxy), timeoutMs)
    })
  }

  /** 结束这次自定义导航转场（可重复调用，第二次无操作）。 */
  private finishNavigationProxy(): void {
    const proxy = this.navigationProxy
    this.navigationProxy = null
    if (proxy !== null) {
      try {
        proxy.finishTransition()
      } catch (error) {
        console.warn(logTag, 'RSS hero finishTransition 失败：', JSON.stringify(error))
      }
    }
  }

  /** customNavContentTransition 被中断/超时结束时调用；正常结束（success=true）不需要处理。 */
  handleNavigationTransitionEnd(success: boolean): void {
    if (!success && this.running) {
      console.warn(logTag, 'RSS hero 自定义导航转场被中断，强制复位')
      this.reset()
    }
  }

  isRunning(): boolean {
    return this.running
  }

  async begin(options: HeroBeginOptions): Promise<void> {
    if (this.running) {
      return
    }
    const stage = this.stage
    if (stage === null) {
      // 理论上不会发生：Overlay 常驻在 NavigationStack 里。退化成直接推页。
      console.warn(logTag, 'RSS hero 没有舞台，退化成直接推页')
      const commit0 = options.commit
      try {
        await commit0()
      } catch (error) {
        console.warn(logTag, 'RSS hero 兜底推页失败：', JSON.stringify(error))
      }
      return
    }

    this.running = true
    console.debug(logTag, 'RSS hero begin title=' + options.title + ' hasOrigin=' + (options.origin !== null))
    this.generation++
    const generation: number = this.generation
    this.commit = options.commit
    this.title = options.title
    this.waiting = false

    // 先把起始几何写进 Overlay，再让它上屏，保证首帧就贴在卡片上（也是无动画的）
    this.stageReady = false
    this.readyResolve = null
    const hasOrigin: boolean = options.origin !== null
    if (options.origin !== null) {
      stage.snap(this.startGeometry(options.origin), true)
    } else {
      stage.snap(this.endGeometry(), false)
    }
    this.active = true
    this.watchdogId = setTimeout(() => {
      console.warn(logTag, 'RSS hero 转场超时，强制恢复首页交互')
      this.reset()
    }, WATCHDOG_MS)

    try {
      if (hasOrigin) {
        await this.waitStageReady(WAIT_READY_TIMEOUT_MS)
        if (generation !== this.generation) {
          return
        }
        // 同一页内把卡片「弹」成全屏（曲线在 Overlay 里，阻尼比 ~0.7，末尾轻微过冲）
        stage.expandTo(this.endGeometry())
        await Task.sleep((HERO_EXPAND_MS + EXPAND_HOLD_MS) / 1000)
        if (generation !== this.generation) {
          return
        }
      }

      // hero 已经是全屏，直接推页；customNavContentTransition 会把这次推页接住，
      // 让目标页不跑系统动画、直接落位在 hero 下面。
      let pushed: boolean = false
      const waitingId: number = setTimeout(() => {
        this.waiting = true
      }, WAITING_DELAY_MS)
      try {
        const commit = this.commit
        pushed = commit === null ? false : await commit()
      } catch (error) {
        console.warn(logTag, 'RSS hero 转场推页失败：', JSON.stringify(error))
        pushed = false
      } finally {
        clearTimeout(waitingId)
      }
      console.debug(logTag, 'RSS hero 推页结束 pushed=' + pushed)
      if (generation !== this.generation) {
        return
      }

      if (pushed) {
        // proxy 交给过来之前，目标页还不一定画完；hero 保持整屏，超时再给个转圈反馈
        const readyWaitingId: number = setTimeout(() => {
          this.waiting = true
        }, WAITING_DELAY_MS)
        let proxy: NavigationTransitionProxy | null = null
        try {
          proxy = await this.waitNavigationProxy(NAV_PROXY_TIMEOUT_MS)
        } finally {
          clearTimeout(readyWaitingId)
        }
        if (generation !== this.generation) {
          return
        }
        this.waiting = false
        if (proxy === null) {
          // 自定义转场一直没来：大概率是系统默认推入动画，等它落定再淡出
          console.warn(logTag, 'RSS hero 未拿到 navigation proxy，按系统推页兜底')
          await Task.sleep(FALLBACK_PUSH_MS / 1000)
        } else {
          // 目标页刚就绪，先让渲染管线落 2~3 帧（48ms@60Hz）再褪 hero；
          // 避免淡出的第一帧目标页还没上屏，把背后的首页带出来
          await Task.sleep(HANDOFF_DELAY_MS / 1000)
        }
        if (generation !== this.generation) {
          return
        }
      }
      this.waiting = false

      // 交叉渐变：hero 表面（含图标/文字）整体淡出，目标页从下面浮出来；失败时露出首页。
      console.debug(logTag, 'RSS hero 开始交叉渐变')
      stage.fadeSurface(0)
      await Task.sleep(HERO_CROSSFADE_MS / 1000)
      if (generation !== this.generation) {
        return
      }
      console.debug(logTag, 'RSS hero 交叉渐变结束')
      this.finishNavigationProxy()
    } finally {
      if (generation === this.generation) {
        this.reset()
      }
    }
  }

  /** 复位。正常流程、失败流程、看门狗都走这里，保证不会残留 active 状态。 */
  private reset(): void {
    this.generation++
    if (this.watchdogId >= 0) {
      clearTimeout(this.watchdogId)
      this.watchdogId = -1
    }
    this.commit = null
    this.waiting = false
    this.active = false
    this.running = false
    this.stageReady = false
    // 等待中的 proxy 也一并叫醒，别让旧流程挂到超时
    const waiter = this.navigationProxyWaiter
    this.navigationProxyWaiter = null
    if (waiter !== null) {
      waiter(null)
    }
    // 导航转场不能悬着：异常路径也要放行，否则导航栈会一直停在「转场中」
    this.finishNavigationProxy()
    const resolve = this.readyResolve
    this.readyResolve = null
    if (resolve !== null) {
      resolve()
    }
  }

  private startGeometry(origin: HeroOrigin): HeroGeometry {
    const geometry: HeroGeometry = {
      x: origin.x,
      y: origin.y,
      width: origin.width,
      height: origin.height,
      radius: RADIUS_START,
      iconSize: ICON_START_SIZE,
      iconX: ICON_START_X,
      iconY: Math.max((origin.height - ICON_START_SIZE) / 2, 0),
      textX: TEXT_START_X,
      textY: Math.max((origin.height - TEXT_START_FONT_SIZE * 1.2) / 2, 0),
      // 故意比卡片右侧留白更宽：首帧靠 hero 表面裁剪，避免长标题在第一帧就换行
      textWidth: Math.max(origin.width - 77, 170),
      fontSize: TEXT_START_FONT_SIZE
    }
    return geometry
  }

  private endGeometry(): HeroGeometry {
    const geometry: HeroGeometry = {
      x: 0,
      y: 0,
      width: watchWidthFp,
      height: watchHeightFp,
      radius: 0,
      iconSize: ICON_END_SIZE,
      iconX: (watchWidthFp - ICON_END_SIZE) / 2,
      iconY: ICON_END_Y,
      textWidth: TEXT_END_WIDTH,
      textX: (watchWidthFp - TEXT_END_WIDTH) / 2,
      textY: TEXT_END_Y,
      fontSize: TEXT_END_FONT_SIZE
    }
    return geometry
  }
}

/**
 * 给 Navigation.customNavContentTransition 用的转场工厂。
 *
 * 只在「hero 正在跑 + 这次是 push」时接管：
 *   - 返回一个 transition：不修改任何页面属性，只把 proxy 交给 hero 状态机；
 *   - hero 在目标页落位后把整屏 hero 淡出，形成交叉渐变；
 *   - 淡出结束后由 hero 调 proxy.finishTransition()，系统才结束这次导航转场。
 * 其它跳转返回 undefined，交回系统默认转场。
 */
export function rssHeroNavTransition(
  from: NavContentInfo,
  to: NavContentInfo,
  operation: NavigationOperation,
  hero: RSSHeroTransition
): NavigationAnimatedTransition | undefined {
  if (operation !== NavigationOperation.PUSH || !hero.isRunning()) {
    return undefined
  }
  console.debug(logTag, 'RSS hero 接管导航转场 from=' + from.index + '/' + from.name + ' to=' + to.index + '/' + to.name)
  return {
    // hero 展开完成后才会 push，这里只需要覆盖「推页 → 交叉渐变」这一段
    timeout: 2000,
    onTransitionEnd: (success: boolean): void => {
      console.debug(logTag, 'RSS hero 导航转场结束 success=' + success)
      hero.handleNavigationTransitionEnd(success)
    },
    transition: (proxy: NavigationTransitionProxy): void => {
      hero.attachNavigationProxy(proxy)
    }
  }
}

/** Area 里的长度在舞台模型下是 number(vp)，这里兜底处理极端情况。 */
function lengthToVp(value: Length | undefined): number {
  if (value === undefined) {
    return 0
  }
  if (typeof value === 'number') {
    const numeric: number = value as number
    return Number.isFinite(numeric) ? numeric : 0
  }
  if (typeof value === 'string') {
    const parsed: number = parseFloat(value as string)
    return Number.isFinite(parsed) ? parsed : 0
  }
  return 0
}

/** 从点击事件里取被点卡片的窗口矩形；取不到返回 null。 */
export function originFromClickEvent(event: ClickEvent): HeroOrigin | null {
  try {
    const area: Area = event.target.area
    const width: number = lengthToVp(area.width)
    const height: number = lengthToVp(area.height)
    if (width <= 0 || height <= 0) {
      return null
    }
    const origin: HeroOrigin = {
      x: lengthToVp(area.globalPosition.x),
      y: lengthToVp(area.globalPosition.y),
      width: width,
      height: height
    }
    return origin
  } catch (error) {
    console.warn(logTag, 'RSS hero 读取点击区域失败：', JSON.stringify(error))
    return null
  }
}
