# JSON Schema 静态生成闭环（Rust，已扩展到多处业务）

## 架构

```text
schemas/generation.json（Douyin / Bili / Local + 测试 Schema）
  -> Rust schema_json：严格 JSON 读取（重复键、null 配置值拒绝）
  -> Rust descriptor：JSONFileDescriptor / JSONObjectDescriptor / JSONFieldDescriptor
                      JSONRootDescriptor / JSONValueDescriptor / JSONTypeDescriptor
  -> Rust generator：Descriptor -> 代码节点树
  -> Rust node：JSONFileNode / JSONImportNode / JSONClassNode / JSONPropertyNode
                JSONFunNode / JSONParameterNode / JSONStatementNode
  -> *.generated.ets：模型构造函数 + 显式逐字段校验/映射
  -> 薄运行库 JsonDecode.ets：JSON 访问边界、路径、错误结果、资源上限
  -> DouyinResponseDecoder：列表/详情信封及业务状态
  -> DouyinFeedMapping：桥接现有 UI DTO
  -> DouyinNativeFeed：实际网络入口
```

**模型及解码器的生成器全部是 Rust。** `scripts/test-jsonschema.mjs` 是测试工具，只把样本转为测试用例并运行实际 ArkTS 源码；不生成模型/解码器，不重新实现校验规则。之前的 JavaScript 生成原型已经移除。

节点树设计参考 TurboTrans `PbNodeTree` 的分层思路（`arkts_generator_node.h` / `arkts_generator.cpp`），独立用 Rust 实现，未移植其 C++ 或 Native/upb 实现。函数体也包含显式 `Const / If / For / Return / Expression` 节点；表达式为字符串叶节点，不声称实现完整的 ArkTS 编译器 AST。缩进、函数签名、类结构、分支和循环的大括号由统一 Writer 输出。

## 文件

| 位置 | 用途 |
| --- | --- |
| `tools/json-gen/` | Rust 编译器、锁定依赖、编译器测试 |
| `schemas/douyin.schema.json` | 抖音 Native / WebView / 缓存 Schema |
| `schemas/bili.schema.json` | 哔哩哔哩接口已迁移部分的 Schema |
| `schemas/local.schema.json` | RSS 根数组、WebView 根标量 Schema |
| `schemas/generation.json` | 生产与测试生成清单 |
| `entry/src/main/ets/common/douyin/schema/` | 自动生成模型及解码器，不手改 |
| `entry/src/main/ets/common/jsonschema/JsonDecode.ets` | 薄共享运行库 |
| `entry/src/main/ets/common/douyin/DouyinResponseDecoder.ets` | `parseFeed / tryParseFeed / parseDetail / tryParseDetail` |
| `entry/src/main/ets/common/douyin/DouyinFeedMapping.ets` | 已校验模型到旧 UI 接口的桥接 |
| `entry/src/main/ets/pages/DouYin/DouyinNativeFeed.ets` | 已替换列表、详情两个 JSON 断言入口 |
| `tests/jsonschema/expansion-cases.json` | 142 组合成样本，覆盖 28 个入口（哔哩哔哩接口、哔哩哔哩媒体、抖音 webFeed、RSS、脚本返回值） |
| `tests/jsonschema/structures.schema.json` | 测试专用 Schema，证明生成器不是硬编码 Douyin |
| `entry/src/test/JsonSchemaExpansion.test.ets` | 跨入口解码测试；内部调用生成的 expansion 用例 |
| `entry/src/test/JsonSchemaExpansionFixtures.generated.ets` | 由 `scripts/jsonschema-expansion-fixtures.mjs` 从 expansion-cases.json 生成 |
| `entry/src/test/jsonschema/generated/` | 测试 Schema 的 Rust 生成产物，仅测试包使用 |

## Schema v1 的明确范围

采用 **JSON 编写的自定义 Schema 子集**，不是完整 JSON Schema 标准，也不是 Zod/Joi 兼容层。第一版不解析 JSON5 注释。

- 嵌套对象：命名 `ref` 和内联 `type: object`；内联对象提升为独立 Descriptor/模型。
- 数组：字符串数组、对象数组、数组套数组、可为 null 的数组项。
- 根节点：`roots` 可声明根数组、标量或 nullable 值，通过 `JSONRootDescriptor` 生成独立入口。
- 标量：string、number、boolean；联合类型目前仅支持标量组合。
- `required` 与 `nullable` 独立；可选字段缺失保持 undefined，nullable 字段显式 null 保持 null。
- `outputName` 完成 wire 字段名到模型字段名的映射，报错路径仍使用原始 wire 名。
- `minLength` 按 ArkTS/JS 字符串 UTF-16 code units 检查；`integer`、`safeInteger` 只作用于数值分支。
- 数字总是检查 finite；字符串 ID 不自动转换为数字；超出安全整数范围的数值 cursor 拒绝。
- 未知响应字段丢弃（`unknownFields: strip`）；不把响应整个对象强转为模型。
- 暂不支持 default、正则、通用转换、对象联合、任意表达式等；未知关键词/不支持的约束在生成期失败，而不是静默忽略。
- 重复键、未知 ref、输出名称冲突、保留标识符、错误 required 列表在生成期拒绝。
- 允许模型递归引用，运行时限制已建模路径的深度。

示例：

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["labels"],
    "properties": {
      "labels": { "type": "array", "items": { "type": "string" } }
    }
  }
}
```

最终收口：9 个媒体/导航入口接入生成校验，1 个无调用旧搜索函数清理。业务直接 JSON.parse 为 0，唯一活动解析点保留在薄运行库。范围与限制见本文后面的「调用与错误契约」与「资源保护」两节。

## 调用与错误契约

```ts
const result = DouyinResponseDecoder.tryParseFeed(text);
if (!result.isSuccess()) {
  const failure = result.getFailure();
  // failure.schema; failure.issues[].code / path / expected / actualType
  console.warn(failure.message);
  return;
}
const feed = result.getOrThrow();
```

`parseFeed` / `parseDetail` 是同一结果 API 的抛错入口。成功只返回全部已验证的真实模型实例；失败不提供半成品模型，`getOrThrow()` 抛出含路径的 `JsonDecodeError`。动态对象断言仅在 JsonNode 内部用于读取 JSON 值，不用于断言业务模型。

典型错误：

```text
TYPE_MISMATCH at $.aweme_list[1].video.play_addr_h264.url_list[1]
expected=string actual=number
```

路径内部保留 `Array<string | number>`，非标识符键以 bracket notation 转义。错误包含元数据，不包含原始响应、JSON 解析器原始异常消息、Cookie 或实际字段值。

端点先验证 status_code，再判断业务状态，再解析成功 payload。合法业务失败不会被误报为缺失 aweme_list。详情还检查请求 ID 与响应 ID 一致。

## 与日志 / Zod / Joi 的对接

解码器内部**不**打日志，保持薄运行库；消费方 catch `JsonDecodeError` 时记录结构化事件：

```ts
const result = DouyinResponseDecoder.tryParseFeed(text);
if (!result.isSuccess()) {
  const failure = result.getFailure();
  const issue = failure.issues.length > 0 ? failure.issues[0] : undefined;
  LogEvents.douyinDecodeFailed({
    operation: 'feed',
    schema: failure.schema,
    issueCount: failure.issues.length,
    code: issue === undefined ? '' : issue.code,
    path: issue === undefined ? '' : issue.pathText(),
    expected: issue === undefined ? '' : issue.expected,
    actualType: issue === undefined ? '' : issue.actualType,
  });
}
```

只记录元数据，不记录原始响应、Cookie、字段值。事件按消费方拆分，保证“一事件一调用点”。

这是 **ArkTS 侧的编译期 Zod/Joi 等价物**，不是 Zod/Joi 兼容层，也不引入运行时依赖：

| 语义 | 本项目 Schema | Zod | Joi |
| --- | --- | --- | --- |
| 对象/字段 | `properties` + `required` | `z.object({...})` | `Joi.object({...}).keys()` |
| 可选 / 可空 | `required` 不含字段；`nullable: true` | `.optional()` / `.nullable()` | `.optional()` / `.allow(null)` |
| 字符串长度 | `minLength` | `.min(n)` | `.min(n)` |
| 整数 / 安全整数 | `integer` / `safeInteger` | `.int()` / `.safe()` | `.integer()` / `.safe()` |
| 标量联合 | `type: ["string","number"]` | `z.union([...])` | `Joi.alternatives()` |
| 未知字段 | `unknownFields: "strip"` | `.strip()`（默认） | `.stripUnknown()` |
| 错误 | `DecodeIssue{code,path,expected,actualType}` | `ZodIssue` | `Joi.ValidationError.details` |

明确不支持 `maxLength / pattern / enum / minimum / maximum / default / transform /
object union / discriminator / 跨文件 ref`；未知关键词在生成期失败。

构建期两层检查：

```bash
node scripts/check-jsonschema-fresh.mjs          # Node 快检 schema 源 SHA-256，不依赖 Rust
node scripts/generate-jsonschema.mjs --check     # 完整 Rust 校验（schema + 生成器代码）
```

日志侧不同：`log-gen` 每次构建都 `--write`，因为行号会随源码移动；JSON Schema 变更低频，
不应让 Rust 成为 Hvigor 的硬依赖。

## 校验与容错边界

本阶段列表使用 **严格模式**：任何已建模字段类型损坏，都使本次解码失败；不会偷偷过滤数组中的坏元素，也不会拿默认值替代类型错误。

缺少 video / video=null 可以是非视频条目，结构允许；业务桥接层明确过滤并计数。缺少某种可选编码会在桥接旧 UI 接口时映射成空 URL 数组，但不会修改生成模型，不等于校验器吞掉错误。播放 URL 优先级、去重、无可播放地址判定仍由现有卡片层负责。分页判断使用原始响应 item 数量，不使用过滤后的数量。

已迁移抖音 WebView/缓存、部分哔哩哔哩接口、RSS/脚本返回值，阶段二扩展与最终收口已合并到本文描述；Hvigor 内没有 JSON 生成任务，Node 版 SHA 快检在 `scripts/test-jsonschema.mjs` 开头执行，Rust 完整生成/校验仍由 `scripts/generate-jsonschema.mjs` 显式执行。Schema 变更后需显式生成。没有执行线上 HTTP/真实播放/点赞/投币等回归。

资源保护：文本上限 2,097,152 UTF-16 code units（JSON.parse 前）；每数组 4096 项；已建模路径深度 48；最多收集 32 条错误。深度限制在 JSON.parse 后，不是流式解析保护，也不扫描被忽略字段；文本长度不是网络字节上限。生产传输层限流/大小限制不在此次实现范围。

## 生成与验证命令

从 Dashiell 根目录执行：

```bash
# 一次生成所有生产和测试 Schema（Node 仅调度 Rust CLI）
node scripts/generate-jsonschema.mjs

# 只生成原来的 Douyin Schema
cargo run --locked --manifest-path tools/json-gen/Cargo.toml

# 检查所有产物是否过期，不写文件
node scripts/generate-jsonschema.mjs --check

# 编译器单测和静态检查
cargo test --locked --manifest-path tools/json-gen/Cargo.toml
cargo clippy --locked --manifest-path tools/json-gen/Cargo.toml --all-targets -- -D warnings

# 测试 Schema 生成
cargo run --locked --manifest-path tools/json-gen/Cargo.toml -- \
  --schema tests/jsonschema/structures.schema.json \
  --out entry/src/test/jsonschema/generated \
  --runtime-import ../../../main/ets/common/jsonschema/JsonDecode

# 主机执行实际 .ets 源码（仅擦除类型，不是 SDK/设备测试的替代品）
node scripts/test-jsonschema.mjs
# 只有修改 tests/jsonschema/expansion-cases.json 后才需要：
node scripts/test-jsonschema.mjs --update-fixtures

# 当前 SDK 编译
 devecocli build --modules entry
 devecocli build --modules entry@ohosTest

# 构建 + 在指定 HarmonyOS 设备执行相同的 Hypium 用例
bash scripts/test-jsonschema-device.sh 127.0.0.1:5555
```

设备脚本构建一律调用 devecocli；其当前未暴露 test-HAP 安装/aa test 子命令，所以仅这两步使用 SDK 自带 hdc。安装为覆盖安装，不卸载、不清空应用数据；只选择 JsonSchemaExpansionFixtures/JsonSchemaExpansion 两个套件，不运行线上接口测试。

生成 CLI 默认路径基于 Cargo manifest 所在项目；给出 `--schema / --out / --runtime-import` 可指定其他布局。写入前完成 Schema 校验；输出有 Schema SHA-256，无时间戳，逐文件临时写入后重命名。不是跨两个文件的事务；需要以生成命令成功退出与 `--check` 为准。
