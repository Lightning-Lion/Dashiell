import { lerp } from '../../common/AnimationLerp';

/**
 * 卡片堆叠的纯几何：把 Scroll 偏移换算成每张卡的相位、位移、缩放。
 *
 * 相位（phase）是这套机制唯一的中间量：
 *   phase = 1  → 正在最前台（位移 0、缩放 1）
 *   phase > 1  → 已经被翻过去（只缩不放，phase 到 3 缩成 0）
 *   phase < 1  → 还在屏幕下方排队（位移 1 屏高，等 phase 涨到 1 顶上来）
 *
 * 相邻卡片的相位差恒为 1，所以 normalizedPosition 直接就是"当前页号（带小数）"。
 * 这里全是纯函数、不 import 任何 UI 能力；相位与缩放的边界值由下面的导出常量单一来源锁定。
 */

/** 相位从 1 涨到 3 的过程中，缩放从 1 收到 0；再往后保持 0。 */
export const CARD_STACK_SCALE_END_PHASE: number = 3;

/** 判定"已经翻到最后一张"的容差：滚动回调是离散的，落点不一定刚好是整数页。 */
export const CARD_STACK_PAGE_SLOP: number = 0.01;

/** 当前页号（带小数）：0 表示第 1 张卡完全居中。 */
export function normalizeScrollPosition(offsetVp: number, pageHeightVp: number): number {
  if (pageHeightVp <= 0) {
    return 0;
  }
  return offsetVp / pageHeightVp;
}

/** 卡片 index 在当前页号下的相位。 */
export function cardPhaseAt(normalizedPosition: number, index: number): number {
  return normalizedPosition + (1 - index);
}

/** 相位 → 纵向位移（vp）：排队时落在一屏之下，上位后归零。 */
export function cardOffsetVpAt(phase: number, pageHeightVp: number): number {
  const remaining: number = 1 - phase;
  if (remaining <= 0) {
    return 0;
  }
  if (remaining >= 1) {
    return pageHeightVp;
  }
  return pageHeightVp * remaining;
}

/** 相位 → 缩放：只有被翻过去（phase > 1）才缩，1→3 线性收到 0。 */
export function cardScaleAt(phase: number): number {
  if (phase <= 1) {
    return 1;
  }
  return lerp(1, CARD_STACK_SCALE_END_PHASE, 1, 0, phase, true);
}

/** 后面是否还有卡片（决定下滑箭头是否出现）。 */
export function hasNextCard(normalizedPosition: number, cardCount: number): boolean {
  const lastIndex: number = cardCount - 1;
  return !((normalizedPosition - lastIndex) > -CARD_STACK_PAGE_SLOP);
}
