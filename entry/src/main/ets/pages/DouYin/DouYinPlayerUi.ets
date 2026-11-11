/**
 * 抖音播放器跨组件共享的 UI 状态。
 * 放在 session 里，外页、内页、菜单都读同一份，避免状态分叉。
 */
export enum DouYinLoopMode {
  Single = 'single',
  Sequence = 'sequence'
}

export enum DouYinMenuLayer {
  None = 0,
  Fan = 1,
  Full = 2,
  Volume = 3,
  Seek = 4,
  Info = 5
}

@ObservedV2
export class DouYinPlayerUi {
  /** 是否处于内页（沉浸态）。外页简介据此显隐。 */
  @Trace immersive: boolean = false
  /** 当前打开的菜单层；页面返回键据此逐层关闭。 */
  @Trace layer: DouYinMenuLayer = DouYinMenuLayer.None
  /** 全屏（裁切铺满）还是适应。 */
  @Trace fullscreen: boolean = false
  /** 全屏拖拽的画面偏移。 */
  @Trace dragX: number = 0
  @Trace dragY: number = 0
  /** 外页表冠推卡的阻力位移，0..1。 */
  @Trace pushProgress: number = 0
  /** 推卡方向：-1 向上（下一条），+1 向下（上一条），0 静止。 */
  @Trace pushDirection: number = 0
}

/** 返回键关闭一层菜单：子层回完整菜单，完整菜单回扇出，扇出回内页。 */
export function closeDouYinLayer(layer: DouYinMenuLayer): DouYinMenuLayer {
  if (layer === DouYinMenuLayer.Info || layer === DouYinMenuLayer.Volume || layer === DouYinMenuLayer.Seek) {
    return DouYinMenuLayer.Full;
  }
  if (layer === DouYinMenuLayer.Full) {
    return DouYinMenuLayer.Fan;
  }
  return DouYinMenuLayer.None;
}
