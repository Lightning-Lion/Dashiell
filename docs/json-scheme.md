# JSON解析

> TS 领域有 Zod、Joi；本项目参考了 `@hadss/turbo-trans-protobuf`、`openharmony-sig/turbo_trans`，实现了自己的解析器。

## 新增JSON解析接入方式

边界需要持续保持清楚：

| 层 | 应该负责 | 不应该负责 |
|---|---|---|
| Schema / 生成代码 | 字段、类型、必填性、嵌套结构的解码 | 请求上下文、接口调用策略 |
| `DouyinResponseDecoder` | 状态语义、响应与请求的一致性、解析入口 | 网络请求、重试、缓存写入、UI 提示 |
| 上层调用方 | 发请求、决定重试、存缓存、向用户展示失败 | 重复实现 JSON 字段解码 |

## 检查脆弱性（有没有残留的JSON.parse()）

`scripts/audit-json-boundaries.mjs`

## 生成代码方式

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

## 实际做一次

在 Dashiell 根目录执行：

```bash
cargo run --locked --manifest-path tools/json-gen/Cargo.toml
```

默认读取：

```text
schemas/douyin.schema.json
```

输出两个文件：

```text
entry/src/main/ets/common/douyin/schema/DouyinModels.generated.ets
entry/src/main/ets/common/douyin/schema/DouyinDecoders.generated.ets
```

也可以执行下面这条命令，连同其他生产和测试 Schema 一起生成：

```bash
node scripts/generate-jsonschema.mjs
```

**两种方式都不会生成或改写 `DouyinResponseDecoder.ets`。** `--out` 只是指定生成产物的目录，并不能让生成器产出这个业务封装文件。

### `DouyinResponseDecoder.ets` 怎么来的？

它需要作为普通业务源码编写、维护，使用以下依赖：

```typescript
import { DecodeContext, DecodeResult, JsonNode } from '../jsonschema/JsonDecode';
import { DouyinSchema } from './schema/DouyinDecoders.generated';
import { DouyinFeedResponse, DouyinDetailResponse, DouyinWebFeedResponse } from './schema/DouyinModels.generated';
```

业务代码参考 [`DouyinResponseDecoder.ets`](../entry/src/main/ets/common/douyin/DouyinResponseDecoder.ets)：它已按上面的依赖写完入口、状态语义与一致性校验。