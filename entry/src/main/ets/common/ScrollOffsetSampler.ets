/**
 * 按帧读取滚动偏移的小工具。
 *
 * 卡片堆叠的位移/缩放必须跟着"每一帧的连续偏移"走；分页吸附、边缘回弹的收尾阶段
 * 偏移也会继续变化，所以这里统一按帧采样，组件只关心"又拿到一个新偏移"。
 *
 * 三条保证：
 * - start() 幂等：重复调用不会叠出两条定时器；
 * - stop() 先补采最后一帧——停稳后 currentOffset() 才是终值，漏采会留下 1~2vp 残差；
 * - readOffset 返回 null（Scroller 还没布局好、或页面已销毁）时丢弃本次，绝不写入 NaN。
 */

/** 采样间隔取整帧，和屏幕刷新同拍（原实现写死 16.7）。 */
export const SCROLL_SAMPLE_FRAME_MS: number = 1000 / 60;

export class ScrollOffsetSampler {
  private timer: number = -1;
  private intervalMs: number;
  private readOffset: () => number | null;
  private onSample: (offset: number) => void;

  constructor(readOffset: () => number | null, onSample: (offset: number) => void,
              intervalMs: number = SCROLL_SAMPLE_FRAME_MS) {
    this.readOffset = readOffset;
    this.onSample = onSample;
    this.intervalMs = intervalMs;
  }

  start(): void {
    this.stopTimer();
    this.sampleNow();
    this.timer = setInterval(() => {
      this.sampleNow();
    }, this.intervalMs);
  }

  /** 停表前补采一帧，让最终停位落在整数页上。 */
  stop(): void {
    this.sampleNow();
    this.stopTimer();
  }

  private sampleNow(): void {
    const offset: number | null = this.readOffset();
    if (offset === null) {
      return;
    }
    this.onSample(offset);
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }
}
