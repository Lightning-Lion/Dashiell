# 日志与源码定位 / Logging with source locations

> 目标：每条业务日志都有 **中文 + English**、结构化字段、级别、tag，
> 并精确打印 **文件:行:列 + 类.方法**；release 构建也不依赖运行时抓栈。

## 1. 为什么用代码生成

ArkTS 没有 C 的 `__FILE__/__LINE__` 宏，也没有公开的 V8 `CallSite` API。
`new Error().stack` 能用，但 release 可能裁剪栈、列号可能偏移，而且每次抓栈有成本。

本项目把“日志调用点”变成构建期信息：

```text
logging/events.json                 事件目录：tag/级别/中英文/字段
        │
        ▼
tools/log-gen                       扫描 + 校验 + 生成
  schema.mjs   事件 schema 校验
  scanner.mjs  找到 LogEvents.<event>(...) 的字面调用
  scope.mjs    解析所在 class/struct + method
  emit.mjs     生成 ArkTS（节点树 + 确定性 writer）
        │
        ▼
entry/src/main/ets/utils/log/LogEvents.generated.ets
        │
        ▼
Hvigor GenerateDashiellLogEvents（PreBuild 之前自动跑）
        │
        ▼
Logger.logAt(level, tag, new LogSite(file, line, column, class, method), ...)
```

生成的事件直接携带 `LogSite`，**运行时零抓栈**。
手写 `Logger.info(...)` 仍保留，用 `Error.stack` 兜底定位。
注意：**只有生成事件能保证 release 精确位置**；手写栈在 release 可能偏移。

## 2. 快速开始

### 2.1 声明事件

编辑 [`logging/events.json`](../logging/events.json)：

```json
{
  "name": "loginSucceeded",
  "tag": "Auth",
  "level": "INFO",
  "zh": "登录成功",
  "en": "login succeeded",
  "fields": [
    { "name": "uid", "type": "string", "zh": "用户 ID", "en": "user id" }
  ]
}
```

字段类型：`string | number | boolean | json`。`required` 默认 `true`。
`error` 默认 `true`，生成的函数末尾会多一个可选的 `error?: Object`。

### 2.2 在调用点写日志

```ts
import { LogEvents } from '../utils/log/LogEvents.generated';

LogEvents.loginSucceeded({ uid: uid });
```

**一个事件必须只有一个调用点。** 生成器会扫描 `LogEvents.<name>(`；
0 个或多个都会让构建失败，并列出位置。需要多处记录时定义两个事件，
例如 `routeNavigate` / `routePendingNavigate`。

### 2.3 生成

构建时自动生成（`entry/hvigorfile.ts` 注册了 `logEventsPlugin()`）：

```bash
# 正常构建即可
hvigorw --mode module -p product=default -p module=entry@default assembleHap --no-daemon
```

手动命令：

```bash
node tools/log-gen/cli.mjs --write --app Dashiell   # 生成
node tools/log-gen/cli.mjs --check --app Dashiell   # CI/本地校验，产物过期则退出 1
node --test tools/log-gen/test/generator.test.mjs
```

不要手改 `LogEvents.generated.ets`；它的头部有 Events/Sites SHA-256。

## 3. 事件 schema

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `name` | 是 | 合法 ArkTS 标识符，全局唯一 |
| `tag` | 是 | hilog tag，≤31 UTF-8 bytes |
| `level` | 是 | `TRACE/DEBUG/INFO/WARN/ERROR/FATAL` |
| `zh` / `en` | 是 | 双语文案，不能为空 |
| `fields` | 否 | 结构化字段；不要拼接动态字符串 |
| `error` | 否 | 默认 `true`，生成 `error?: Object` 参数 |
| `class` / `method` | 否 | 覆盖扫描结果（异常排版时使用） |

校验在生成前完成：重复事件名、未知字段类型、保留字、非法标识符、
`tag` 超长、缺失中英文都会直接失败，不会写出半成品。

## 4. 生成结果示例

```ts
export class LogEvents {
  private static readonly SITE_APP_CREATE: LogSite = new LogSite(
    "entry/src/main/ets/entryability/EntryAbility.ets",
    36,
    7,
    "EntryAbility",
    "onCreate",
    "appCreate",
  );

  static appCreate(fields: AppCreateFields): void {
    Logger.logAt(LogLevel.INFO, "App", LogEvents.SITE_APP_CREATE,
      L("应用启动", "app created"), [
      F("version", fields.version),
      F("debug", fields.debug),
      F("device", fields.device),
      F("api", fields.api),
      F("session", fields.session),
    ]);
  }
}
```

输出（PRETTY；release 默认 COMPACT）：

```text
20:34:10.486  INFO/信息  App  #000001  tid=26212
    evt     appCreate
    应用启动 / app created
    src     entry/src/main/ets/entryability/EntryAbility.ets:36:7  EntryAbility.onCreate
    fields  version=1.2.0(1000009)  debug=true  device=RTS-AL00  api=23  session=...
```

## 5. 运行时 Logger

实现位于 `entry/src/main/ets/utils/log/`：

| 文件 | 职责 |
| --- | --- |
| `LogCore.ets` | 级别/格式/双语/字段/LogSite/Record/Config |
| `LogSourceLocator.ets` | 手写日志的栈解析与路径归一化 |
| `LogErrorCapture.ets` | Error/非 Error、code/httpStatus/stack/cause 快照 |
| `LogMask.ets` | token/手机号/验证码/Cookie 等字段脱敏 |
| `LogFormatter.ets` | COMPACT / PRETTY / JSON 三种格式 |
| `Logger.ets` | hilog + 内存环形缓冲 + timer + scope |
| `LogAppConfig.ets` | 唯一按 App 不同的配置（appName/defaultTag） |
| `LogEvents.generated.ets` | 构建期生成，禁止手改 |

初始化（`EntryAbility.onCreate`）：

```ts
Logger.init({ debug: DevFlags.isDebugBuild, appVersion: version });
Logger.getConfig().extraMaskKeys = [
  'sessdata', 'bili_jct', 'dedeuserid', 'ttwid', 'odin_tt', 'ms_token',
  'passport_csrf_token',
];
```

- `minLevel`：低于该级别直接返回，不构造 Record、不抓栈、不格式化。
- `format`：`COMPACT` 单行、`PRETTY` 多行、`JSON` 每行一个对象。
- `language`：`BOTH`（默认）、`ZH`、`EN`。
- `includeMeta`：PRETTY 额外打印 ISO 时间、pid、app、build、device、api、session。

### 手写日志（兜底）

```ts
Logger.warn('Api', L('请求失败', 'request failed'),
  [F('service', 'AuthService'), F('status', 401)], err);
```

手写入口会用 `Error.stack` 找调用点；`LogSourceLocator` 兼容：

```text
at Foo.bar (entry|entry|1.0.0|src/main/ets/pages/Foo.ets:12:5)
at Foo.bar (entry/src/main/ets/pages/Foo.ets:12:5)
at anonymous (ets/pages/Foo.ets:12:5)
at entry/src/main/ets/pages/Foo.ets:12:5
```

按**文件路径**跳过 `utils/log/` 内部帧，不按固定层数跳。
release 下如果栈不可用，只能退化为 `unknown:0:0`；需要 release 精确位置时请使用
`LogEvents`。

### 作用域 / 计时 / 错误

```ts
const log = Logger.scope('Sync', 'push');
log.info(L('开始推送', 'push start'), [F('bookId', bookId)]);

Logger.time('sync');
// ...
Logger.timeEnd('sync', LogLevel.INFO, [F('books', 3)]);
```

错误快照包含 `name/message/code/httpStatus/stack/props/cause`，
非 Error 对象也能提取 `message/code`；格式化器对 `token/phone/password`
等字段名自动脱敏。

### 内存缓冲 / 导出

`Logger.recent(limit)`、`Logger.exportText()`、`Logger.clearMemory()`。
默认保留最近 300 条渲染后的文本（不保留原始对象，避免敏感值滞留）。

## 6. Hvigor 集成

[`entry/log-events-plugin.ts`](../entry/log-events-plugin.ts) 注册：

```ts
node.registerTask({
  name: 'GenerateDashiellLogEvents',
  run: () => { /* execFileSync(node tools/log-gen/cli.mjs --write --app Dashiell) */ },
  postDependencies: ['default@PreBuild'],
});
```

构建顺序：

```text
GenerateDashiellLogEvents → PreBuild → CompileArkTS → ...
```

- 生成失败 = 构建失败，避免把过期行号打进 HAP。
- 每次构建都扫描；源码移动后行号自动更新。
- 生成器先完成全部校验，再写临时文件并 rename，失败不会破坏旧产物。
- `--check` 用于 CI 或提交前检查产物是否与源码一致。

## 7. 源码定位的边界

1. 调用必须写成字面量 `LogEvents.<name>(`。别名、反射、模板字符串内调用不会被扫描。
2. 多行调用以 `LogEvents` 所在行/列为准。
3. `class/method` 由轻量级 brace-aware 扫描器推断；多行方法签名、嵌套 `if/for`、
   `.then(() => {})` 内部都能归属到外层方法。极端排版可用事件里的
   `class`/`method` 覆盖。
4. 扫描器忽略注释和字符串；`foo.LogEvents.x()` 不算调用。
5. 生成文件自身不扫描，避免自我引用。
6. 手写日志的 `Error.stack` 定位是兜底方案；release 会重排代码。

## 8. JSON 解码失败与日志

`common/jsonschema/JsonDecode.ets` 保持薄运行库，**不**在解码器内部打日志。
消费方 catch `JsonDecodeError` 时记录结构化事件：

```ts
LogEvents.biliDecodeFailed({
  operation: 'search',
  schema: error.schema,
  issueCount: error.issues.length,
  code: issue.code,
  path: issue.pathText(),
  expected: issue.expected,
  actualType: issue.actualType,
});
```

只记录 schema/issue 元数据；**绝不**记录原始响应、Cookie、Token、字段值。
事件按消费方拆分（`biliDecodeFailed` / `douyinDecodeFailed` / `zhihuDecodeFailed` /
`localDecodeFailed`），保证每个事件只有一个调用点。

## 9. 真机日志

```bash
# 只看业务 tag
hdc shell hilog -T App,Api,Auth,Db,Rss,Bili,Douyin,Json,Ui -x

# 清空后重启
hdc shell hilog -r
hdc shell aa start -a EntryAbility -b com.dalton.dashiell
```

hilog 自带前缀是 domain/tag，源码位置在消息体 `src` 行；DevEco Log 里可以直接搜索
`entry/src/main/ets/`。

## 10. 与手表端应用的共享文件

逐字节一致：

- `tools/log-gen/{cli,schema,scanner,scope,emit}.mjs`、`test/generator.test.mjs`、`README.md`
- `entry/src/main/ets/utils/log/{LogCore,LogFormatter,LogMask,LogErrorCapture,LogSourceLocator,Logger}.ets`

允许差异：`LogAppConfig.ets`、`logging/events.json`、`LogEvents.generated.ets`、
`EntryAbility` 的 `Logger.init` 参数。改共享文件后两端都要跑
`node tools/log-gen/cli.mjs --check` 与生成器单测。
