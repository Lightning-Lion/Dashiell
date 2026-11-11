/**
 * 本地开发开关默认值：随仓库提交，全部关闭。
 *
 * 需要 dev UI 或启动直达时直接改这里的常量并重新构建；
 * release 构建由 DevFlags.ets 强制全部关闭，不依赖本文件的取值。
 */
export const DEV_DIRECT_ENTRY: string = '';

// 抖音本地 dev UI 总开关：精选面板、表冠读数面板、登录页覆盖层掀开，三者同时生效。
// 表冠面板本身始终挂载（它是外页表冠焦点的唯一持有者），本开关只控制可见性。
export const DEV_DOUYIN_DEV_UI: boolean = false;
