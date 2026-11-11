# 本地开发配置（启动直达）

## 启动直达

目标登记在 `entry/src/main/ets/common/dev/DirectEntry.ets`：`NavigationStack.aboutToAppear()` 在导航栈为空时调用 `applyDirectEntry()`，命中即压栈并保留首页返回链路，key 未命中只打警告、不崩溃。接入新模块 = 加一个具名 push 函数 + 在 `directEntryTargets` 里加一行，再把 `DEV_DIRECT_ENTRY` 设成该 key。带函数/类入参的路由不能登记，因为路由参数会被物化成普通对象、方法会丢失。

| key | 目标 |
|---|---|
| `zhihu-hot` | 知乎热榜 - 全站 |
| `zhihu-daily` | 知乎日报 |
| `ithome` | IT之家 |
| `3dmgame` | 3DM - 新闻中心 |
| `douyin-jingxuan` | 抖音菜单 + 精选页 |
| `douyin-login` | 抖音登录页 |
| `bili-home-login` | 哔哩哔哩首页（登录链路） |
| `bili-home-guest` | 哔哩哔哩首页（免登录） |
| `bili-login-required` | 哔哩哔哩登录中间页（栈底为免登录首页） |
| `settings` | 个性化设置 |

启动后用 `devecocli log --keyword DEV_DIRECT_ENTRY` 可以确认实际命中的目标（`key=... title=...`）。