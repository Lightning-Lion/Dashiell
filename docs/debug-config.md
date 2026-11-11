# 开发配置

## 日志

生产版本目前关闭了全部日志（现有输出走 `console.debug()`）。后续计划让生产包也打印不泄露凭据的结构化日志，规则见 [logging.md](logging.md)。

## 统一 Debug/Release 开关（DevFlags）

`entry/src/main/ets/common/dev/DevFlags.ets` 是**唯一**的 debug/release 判定入口。
业务代码只 import `DevFlags`，不再直接读 `BuildProfile` 或 `LocalDevConfig`：

- `BuildProfile.DEBUG === false`（release）时，所有开关恒为关：即使本地 `LocalDevConfig` 残留开启项，
  或者 HAP 用 debug 证书签名，dev UI 和调试 Want 都不会生效。
- `LocalDevConfig.ets` 随仓库提交、默认全关，只表达「本地想开什么」；是否生效由 `DevFlags` 裁决。

| 开关 | 作用 |
|---|---|
| `DevFlags.isDebugBuild` | 构建模式；DevTools 接入也只看它 |
| `DevFlags.directEntry` | 启动直达 key（原始值 `DEV_DIRECT_ENTRY`） |
| `DevFlags.douyinDevUI` | 抖音本地 dev UI 总开关：精选面板 + 表冠读数面板 + 登录页覆盖层掀开（原始值 `DEV_DOUYIN_DEV_UI`） |

只剩这两个开关，没有生成脚本：直接改 `entry/src/main/ets/common/dev/LocalDevConfig.ets` 里的常量，再重新构建。
`DEV_DOUYIN_DEV_UI` 是合在一起的：打开它三处会同时生效，不能单独只开其中一项。

## 抖音精选调试面板

面板显示已加载条数，以及「更多」「刷新链接」两个手动按钮（在生产里这两个动作分别由滑到底自动加载、`DouyinNativeFeed` 自己完成）。

由 `DevFlags.douyinDevUI`（本地原始开关 `DEV_DOUYIN_DEV_UI`）控制显隐，
默认关闭且只在 debug 构建生效；要打开就把 `DEV_DOUYIN_DEV_UI` 改成 `true` 再重新构建
（可同时把 `DEV_DIRECT_ENTRY` 设成 `douyin-jingxuan` 直达该页）。同一个开关也会掀开表冠面板和登录页覆盖层。

关掉面板不影响用户侧：滑到最后一条时播放器会显示「正在加载更多」的转圈并自动请求下一页；失败则显示原因和「重试」按钮（自动加载失败后不会自己重试）。

## 抖音表冠调试面板

参考实现「焦点即路由」的做法：同一时刻只有一个表冠焦点持有者。

- 外页：常驻面板 `DouYinCrownDebugPanel` 持有焦点，`onDigitalCrown` 驱动推卡（`DouYinCrownPager`），不再调音量。
- 内页：`DouYinImmersiveView` 内自己的面板持有焦点，只驱动音量；外页面板失焦。
- `List` 保持 `focusable(false)`，只响应触摸滑动；表冠事件不会落到它上面。
- 面板先 `stopPropagation()`，再累加/刷新读数。
- 根容器（`DouVideoPlayer` 外层 Column）不再持有表冠焦点，只做布局。

面板的「推+30° / 推-30°」按钮用于在没有物理表冠的模拟器上验证推卡；内页左上角的「音量- / 音量+ / 模拟表冠」用于验证音量 HUD 与系统音量。

`DevFlags.douyinDevUI`（本地原始开关 `DEV_DOUYIN_DEV_UI`）只控制面板的**可见性**，绝不让它消失：

- 开：面板显示「焦点状态 / 模式 / 累计角度 / 角速度 / 动作」，并显示模拟推卡按钮。
- 关：面板缩成 1 像素 + 透明藏起来，但仍然挂载、仍然获焦捕获表冠；外页推卡/内页音量行为不变。

release 构建恒为关；面板本身始终挂载，它是外页表冠焦点的唯一持有者，不能用 `if (dev)` 整块删掉。
`DEV_DOUYIN_DEV_UI` 与 `DEV_DIRECT_ENTRY` 都在 `LocalDevConfig.ets` 里改，重新构建生效。

参考里的「点击重新获焦」按钮不需要：外页 `onAppear`、退出内页（`setImmersive(false)`）都会调用 `requestFocus(DOUYIN_CROWN_PANEL_ID)` 把表冠焦点收回面板；内页则由 `DouYinImmersiveView` 在 `aboutToAppear` 与关闭菜单层时收回自己的面板。

## 直接跳转功能

便于在模拟器或真机上跳过逐级点击，启动后直接进入目标页面。
入口读 `DevFlags.directEntry`（本地原始值 `DEV_DIRECT_ENTRY`），release 构建恒为空，不会直达任何页面。

把 `LocalDevConfig.ets` 里的 `DEV_DIRECT_ENTRY` 置为空串即可关闭跳转。

## RSS 订阅表调试 Want

排查「添加 RSS 源」这类需要点界面的持久化问题时，用这个 Want 直接走同一条
repository/DAO 链路，不依赖输入法：`EntryAbility` 的 `onCreate` / `onNewWant` 读
`--ps probe rss-*`，只在 debug 构建生效，release 收到也忽略。

```sh
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
BUNDLE=com.dalton.dashiell

# 查看当前订阅（重启后用它确认是否持久化）
"$HDC" shell "aa force-stop $BUNDLE"
"$HDC" shell "aa start -b $BUNDLE -a EntryAbility --ps probe rss-list"

# 添加（默认知乎热榜；可传 --ps stableId <uuid> 指定别的源）
"$HDC" shell "aa start -b $BUNDLE -a EntryAbility --ps probe rss-add"

# 清空（调试收尾）
"$HDC" shell "aa start -b $BUNDLE -a EntryAbility --ps probe rss-clear"
```

结果同时写 `console.debug`（`🚩 rss debug {...}`）和私有目录 `rss-debug-result.json`
（`ok/mode/origin/requested/before/after/reason/timestamp`）。
注意路径是 app 级 files 目录，不带 `haps/entry`：

```sh
"$HDC" shell "cat /data/app/el2/100/base/com.dalton.dashiell/files/rss-debug-result.json"
```

`rss-add` 刻意用 `@ObservedV2` + `@Trace` 的代理数组调用 `replaceOrder`，复现界面里
`enabledRSSItemsId` 的真实入参形状：relationalStore 只接受普通数组，代理数组曾让
`DELETE ... WHERE station_id NOT IN (?)` 的绑定参数变成 0，整条事务回滚、界面报
「无法保存RSS源」。改动 `RdbSqlDatabase.toBindArgs` 后先跑
`aa test -s class storageBindArgs`（`entry/src/test/StorageBindArgs.test.ets`），再用上面的
Want 验证重启后 `rss-list` 仍能读到。

## 抖音 Cookie 调试 Want

调试/QA 的 Cookie 只通过显式 Want 导入，导入后直接写入 WebView 的 `WebCookieManager`。
运行时唯一来源是 `DouyinCookieStore.read()` → `WebCookieManager.fetchCookie('https://www.douyin.com/')`；
不再写 `douyin-cookie.txt` / `douyin-web-cookies.json`，也没有源码级开发 Cookie。

入口是 `EntryAbility` 的 `onCreate` / `onNewWant`，只在 debug 构建生效：
`DevFlags.isDebugBuild` 为 false（只看 `BuildProfile.DEBUG`，不再看 `applicationInfo.debug`）时
只写一条忽略日志，不读取、不写入任何 Cookie。用 debug 证书签名的 release HAP 同样会被拒绝。

- action：`com.dalton.dashiell.debug.IMPORT_DOUYIN_COOKIES`
- Cookie 参数：`--ps cookie 'sessionid=...; UIFID=...'`（单行 Cookie 请求头；上限 16 KB）
- 清理参数：`--ps remove 'name1,name2'`（只在 www/lf-zt/lf-rc1 三个域上把指定名字过期）
- 检查参数：`--ps inspect 1`（只返回 WebView Cookie **名字**，不返回值；用于重启后验证持久化）
- 结果：应用私有目录 `douyin-cookie-import-result.json`，只含计数、域名、Cookie/登录标记**名字**，绝不含值
- `--ps source` 已不再识别：传了会被直接忽略，没有任何输入时走 `no-input`
- 导入成功条件：至少写入一条、`saveCookieSync()` 成功、`fetchCookieSync()` 能验证到

### 手动命令

```sh
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
BUNDLE=com.dalton.dashiell
BASE=/mnt/debug/100/debug_hap/$BUNDLE/data/storage/el2/base/files
COOKIE="$(cat /private/path/douyin-cookie.txt)"   # 必须单行、非空、<=16 KB

"$HDC" -t 127.0.0.1:5555 shell "aa force-stop $BUNDLE"
"$HDC" -t 127.0.0.1:5555 shell "aa start -b $BUNDLE -a EntryAbility \
  -A com.dalton.dashiell.debug.IMPORT_DOUYIN_COOKIES \
  --ps cookie '$COOKIE'"

# 看结果（没有 Cookie 值）
"$HDC" -t 127.0.0.1:5555 shell "cat $BASE/douyin-cookie-import-result.json"

# 只检查 Cookie 名字（force-stop/重启后可用它确认持久化）
"$HDC" -t 127.0.0.1:5555 shell "aa start -b $BUNDLE -a EntryAbility \
  -A com.dalton.dashiell.debug.IMPORT_DOUYIN_COOKIES \
  --ps inspect 1"
"$HDC" -t 127.0.0.1:5555 shell "cat $BASE/douyin-cookie-import-result.json"
```

应用已经在运行时不必 force-stop，直接发同一条 `aa start`，结果里的 `origin` 会是 `onNewWant`。
`--ps cookie` 的值会进入设备进程参数和 shell 历史；只用短命测试账号 Cookie，导入后 force-stop，
不要用共享 shell。

### 支持格式

- **单行 Cookie 请求头**（推荐）：`name=value; name2=value2`，域按 `www.douyin.com` 处理。
- **单行 JSON**：`[{domain,name,value}, ...]` 或 `{ "cookies": [...] }`，仍受 16 KB 限制。
- 多行 TSV 不再通过 shell/Want 传；需要完整多域登录态时走交互式 WebView 登录。

只接受 `douyin.com`、`yhgfb-cn-static.com` 及其子域；域外条目在结果里计入 `outOfScope`。

### 持久化与登录态

- 导入的 Cookie 按域写入 WebCookieManager，设置一年 `Max-Age`，并调用 `saveCookieSync()`。
  设备验收要求 force-stop 后重启仍能用 `fetchCookie` 读到。
- 登录标记只看 `passport_assist_user` / `sessionid` / `sessionid_ss` / `sid_tt`，且值非空。
  `user_info`、`HasUserLogin`、`ttwid` 等**不算**登录态。
- `DouyinCookieStore.read()` 只读 WebView；旧 `douyin-cookie.txt`、`douyin-web-cookies.json`
  和 `DOUYIN_DEV_COOKIE` 都不再参与读取。
- 成功导入后会 best-effort 删除规范/旧 files 目录里的这两个旧文件，结果里的
  `legacyFilesRemoved` 记录删除数量；删除失败不影响导入结果。
- 结果字段：`origin/ok/reason/format/kept/domains/nativeChars/webView*/markers/cookieNames/removed/legacyFilesRemoved/timestamp`。

2026-10-21 的历史实测（旧文件路径）只用于说明抖音会话标记；当前实现改为 Want 直接写 WebView，
仍以 `passport_assist_user`/`sessionid`/`sessionid_ss`/`sid_tt` 判定登录态。
`user_info`/`HasUserLogin` 本身仍不算登录态。

### 清理与安全

```sh
# 只过期指定名字，不碰其它 Cookie
"$HDC" -t 127.0.0.1:5555 shell "aa start -b $BUNDLE -a EntryAbility \
  -A com.dalton.dashiell.debug.IMPORT_DOUYIN_COOKIES \
  --ps remove 'debug_probe,debug_warm,theme'"
```

- 日志只打印 `origin/ok/reason/format/kept/domains/nativeChars/webView*/markers/removed/cookieNames 数量/legacyFilesRemoved`，不打印值。
- 结果文件不含值；不再生成 Cookie 文件。
- release 构建忽略同一 action。

## 隐藏覆层

哔哩哔哩登录、抖音登录、知乎有覆层

方便观察ArkWeb是否正常加载还是崩溃了

抖音登录的覆盖层由 `DevFlags.douyinDevUI`（本地原始开关 `DEV_DOUYIN_DEV_UI`）控制：

- 关（默认，也是 release 恒态）：网页被整块盖住，`debugIsShow` / `debugIsHit` 默认 `true`，与生产一致。
- 开：跳过覆盖层露出 WebView，左上角出现一个小 Toggle；Toggle 只控制覆盖层的压暗透明度，方便观察 ArkWeb。
- `setWebDebuggingAccess()` 跟随 `DevFlags.isDebugBuild`：debug 构建允许 DevTools，release 构建关闭。

`debugIsShow`/`debugIsHit` 仍是运行时状态，默认 `true` 即生产表现，不要为了「debug」把它们改掉。