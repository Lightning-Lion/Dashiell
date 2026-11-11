/**
 * 外页表冠推卡的纯逻辑：把角度增量换算成“齿感”“落位”“阻力进度”。
 *
 * 规则：
 * - 转动约 STEP_DEGREES 才算推满一张卡；
 * - 两次落位至少间隔 COOLDOWN_MS，快速连转不会一次跳好几条；
 * - 每 TICK_DEGREES 一次齿感，最快 TICK_MIN_MS 一次；
 * - 反向转动立即清零，避免来回抖动累计出两次推卡；
 * - 落位后剩余角度直接丢弃。
 */
export const CROWN_STEP_DEGREES = 165;
export const CROWN_COOLDOWN_MS = 700;
export const CROWN_TICK_DEGREES = 33;
export const CROWN_TICK_MIN_MS = 80;

export interface CrownPagerUpdate {
  /** 本次事件是否应落位：-1 上一条，+1 下一条，0 不落位。 */
  commit: number;
  /** 阻力进度 0..1。 */
  progress: number;
  /** 阻力方向：-1 向上，+1 向下，0 静止。 */
  direction: number;
  /** 本次是否应发一记齿感触感。 */
  tick: boolean;
}

export class DouYinCrownPager {
  private acc: number = 0;
  private lastCommitMs: number = 0;
  private lastTickMs: number = 0;
  private tickIndex: number = 0;

  begin(): void {
    this.acc = 0;
    this.tickIndex = 0;
  }

  update(degree: number, now: number, animating: boolean): CrownPagerUpdate {
    if (degree !== 0 && this.acc !== 0 && this.sign(degree) !== this.sign(this.acc)) {
      this.acc = 0;
      this.tickIndex = 0;
    }
    this.acc += degree;

    const abs = Math.abs(this.acc);
    if (abs >= CROWN_STEP_DEGREES && now - this.lastCommitMs >= CROWN_COOLDOWN_MS && !animating) {
      const commit = this.acc < 0 ? 1 : -1;
      this.acc = 0;
      this.tickIndex = 0;
      this.lastCommitMs = now;
      return { commit, progress: 0, direction: 0, tick: false };
    }

    const progress = Math.min(abs / CROWN_STEP_DEGREES, 1);
    const direction = this.acc === 0 ? 0 : this.sign(this.acc);
    let tick = false;
    const nextTickIndex = Math.floor(abs / CROWN_TICK_DEGREES);
    if (nextTickIndex > this.tickIndex && now - this.lastTickMs >= CROWN_TICK_MIN_MS && abs > 0) {
      this.tickIndex = nextTickIndex;
      this.lastTickMs = now;
      tick = true;
    }
    return { commit: 0, progress, direction, tick };
  }

  end(): void {
    this.acc = 0;
    this.tickIndex = 0;
  }

  private sign(value: number): number {
    return value < 0 ? -1 : 1;
  }
}
