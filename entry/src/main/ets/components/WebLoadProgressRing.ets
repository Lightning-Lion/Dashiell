import { watchWidthVp } from '../common/ScreenSize';

/**
 * 网页加载进度的环形进度条：绕圆形表盘一圈，弧长跟着 Web 的 onProgressChange 走。
 *
 * 上报是稀疏的（ArkWeb 只在若干节点回调一次），挑战页还可能几十秒停在同一个值上，所以
 * 这里按固定步长向目标值逼近，把每次跳变摊成连续滑动——"插帧"就是这件事：每 RING_TICK_MS
 * 走一小步，每步吃掉剩余差值的一个固定比例，起步快、接近目标时慢，肉眼看不到台阶。
 * 组件自带的 enableSmoothEffect 再对每一步做一次平滑，两者叠加后是连续的。
 *
 * 局限：插帧靠主线程定时器，主线程被 Web 页面占满时会退化成"只在上报时更新"（知乎挑战页
 * 实测 47 秒里 1.5 秒的轮询只跑了 4 次，见 ZhihuQuestionLoader）。声明式动画那条路在这里
 * 用不上：弧长画的是真实进度，而 Progress 的进度值不支持用 animateTo 插值
 * （DevEco FAQ faqs-arkui-508）。
 */

/** 外径比屏幕小一圈，让描边落在表盘边缘内侧，不被圆角切掉。 */
const RING_DIAMETER_VP: number = watchWidthVp - 6;
const RING_STROKE_VP: number = 3;
/** 未走到的部分：淡淡一圈，让"整圈"这个形状先立住。 */
const RING_TRACK_COLOR: string = '#33FFFFFF';

/** 插帧步长。上报间隔从几百毫秒到几十秒不等，这里固定 16.67ms 一步。 */
const RING_TICK_MS: number = 1000/60;
/** 每步吃掉剩余差值的比例：十来步（60fps 下约 0.2 秒）走完大半。 */
const RING_EASE: number = 0.14;
/** 差值小到这个程度就直接贴上去，省掉无限逼近。 */
const RING_SNAP: number = 0.2;

/** 上报值停住超过这个时间就算停滞，弧长开始自己往前爬。 */
const RING_STALL_MS: number = 2500;
/** 爬升的上限：始终留一截，不假装已经加载完。 */
const RING_DRIFT_CAP: number = 92;
/** 爬升的时间常数：爬完到上限的 63% 需要这么久。按步长折算，改 RING_TICK_MS 不影响快慢。 */
const RING_DRIFT_TAU_MS: number = 18000;

@ComponentV2
export struct WebLoadProgressRing {
  /** 网页加载进度 0-100，来自 Web 的 onProgressChange。 */
  @Param @Require progress: number
  @Param @Require color: ResourceColor

  /** 当前画出来的进度，向 this.ceiling 逼近。只有它变才触发重绘。 */
  @Local private shown: number = 0
  /** 逼近的目标：上报值，或停滞时爬升出来的值。 */
  private ceiling: number = 0
  private drift: number = 0
  private lastReport: number = -1
  private reportedAt: number = 0
  private timer: number = -1

  aboutToAppear(): void {
    this.reportedAt = Date.now();
    this.timer = setInterval(() => {
      this.step();
    }, RING_TICK_MS);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private step(): void {
    const now = Date.now();
    const report = this.progress;
    if (report !== this.lastReport) {
      // 上报值是权威的，高和低都跟随：进度变小说明文档重新开始了，与其冻在旧的高位上，
      // 不如跟着退回去再爬。
      this.lastReport = report;
      this.reportedAt = now;
      this.drift = report;
      this.ceiling = report;
    } else if (now - this.reportedAt >= RING_STALL_MS) {
      // 按步长折算而不是按 tick 计数：改插帧频率时爬升的快慢不变，而且主线程卡住漏掉若干
      // 步之后也只补一步的量——卡住的时候不该跳。
      const share = RING_TICK_MS / RING_DRIFT_TAU_MS;
      this.drift = this.drift + (RING_DRIFT_CAP - this.drift) * share;
      if (this.drift > this.ceiling) {
        this.ceiling = this.drift;
      }
    }
    const gap = this.ceiling - this.shown;
    if (Math.abs(gap) <= RING_SNAP) {
      this.shown = this.ceiling;
      return;
    }
    this.shown = this.shown + gap * RING_EASE;
  }

  build() {
    Progress({ value: this.shown, total: 100, type: ProgressType.Ring })
      .style({ strokeWidth: RING_STROKE_VP, enableSmoothEffect: true })
      .color(this.color)
      // Ring 类型下它是那圈底环，不是背景方块
      .backgroundColor(RING_TRACK_COLOR)
      .width(RING_DIAMETER_VP)
      .height(RING_DIAMETER_VP)
  }
}
