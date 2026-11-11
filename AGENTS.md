# AGENTS.md

本文件给在本仓库工作的 agent 一个最小入口；细节放到 `docs/`，这里只放容易踩坑的约定。

## 必读

- [持久化存储](docs/persistence.md)：改数据库 schema、Key、时间戳或一次性迁移前先读。业务代码只能走 `common/storage/*Repository`，不得直接 import `preferences`/`PersistenceV2`；旧数据只迁移、不删除。
- [调试 Want](docs/debug-config.md#抖音-cookie-调试-want)：改 `EntryAbility` 的 `onCreate`/`onNewWant`、`common/douyin/DouyinCookieDebugImport.ets` 或本地调试开关前先读。显式 Want 导入只在 debug 构建生效（release 及 debug 证书签名的 release HAP 都忽略）；Cookie 只写 `WebCookieManager`，不再落 `douyin-cookie.txt`/`douyin-web-cookies.json`；`--ps source` 不再识别。结果文件只含计数、域名和登录标记**名字**，绝不含 Cookie 值。
- [日志与源码定位](docs/logging.md)：改 `logging/events.json`、`tools/log-gen/`、`entry/src/main/ets/utils/log/` 或任何 `LogEvents.*` 调用点前先读。事件必须“一事件一调用点”、中英文必填；生成文件 `LogEvents.generated.ets` 禁止手改，构建期由 Hvigor `GenerateDashiellLogEvents` 重写；`--check`/生成器单测必须过。日志与 JSON 校验的共享边界见 [logging.md](docs/logging.md) 第 10 节。

## 约定

- 新增全屏错误页时，在 struct 顶部写清“背景继承自哪里”；错误页颜色对照表不再单独维护。
- 错误页需要跟页面同色系的 ArcButton 时，显式传 `SettingsButton` 的 `arcBackgroundColor` / `arcFontColor` / `arcShadowColor`，不要假设主题会自动生效。
- 已审计的 ArcButton 站点必须显式传 surface palette（哔哩哔哩首页青、哔哩哔哩粉、brand 玫红、抖音红、琥珀、`ErrorPrompt` 中性石墨）；默认系统蓝只作为未来调用方的 fallback。
- 日志优先级：关键路径用 `LogEvents`（release 精确位置）；重复 UI/动画噪声用 `Logger.debug/info` 手写；不要把动态值拼进文案，不要记录 token/Cookie/手机号/原始 JSON。新增解码失败日志只带 `schema/issueCount/code/path/expected/actualType`。
