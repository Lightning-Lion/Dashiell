import BuildProfile from 'BuildProfile';
import {
  DEV_DIRECT_ENTRY,
  DEV_DOUYIN_DEV_UI
} from './LocalDevConfig';

/**
 * 唯一的 debug/release 判定入口。
 *
 * 业务代码只从这里取开关，不要直接 import `BuildProfile` 或 `LocalDevConfig`。
 * release 构建（BuildProfile.DEBUG === false）下所有开关恒为关：
 * 即使本地 LocalDevConfig 残留了开启项、或者 HAP 用 debug 证书签名，
 * dev UI、调试 Want 都不会生效。
 *
 * LocalDevConfig.ets 随仓库提交、默认全关，只表达「本地想开什么」；
 * 是否真的生效由这里统一裁决。
 */
const IS_DEBUG_BUILD: boolean = BuildProfile.DEBUG;

export class DevFlags {
  static readonly isDebugBuild: boolean = IS_DEBUG_BUILD;

  static readonly directEntry: string = IS_DEBUG_BUILD ? DEV_DIRECT_ENTRY : '';

  static readonly douyinDevUI: boolean = IS_DEBUG_BUILD && DEV_DOUYIN_DEV_UI;
}
