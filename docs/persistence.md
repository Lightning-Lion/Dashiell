# 持久化存储（RDB）

本仓库的设置、标记、列表和缓存元数据统一存放在 HarmonyOS `relationalStore`（RDB/SQLite）中。
修改 schema、Key、迁移逻辑前先读本文。

## 边界

进入 RDB：

- 隐私政策同意、哔哩哔哩登录过至少一次、个性化推荐开关、抖音循环模式。
- 哔哩哔哩搜索历史、RSS 订阅列表。
- 哔哩哔哩首页「刚在其他设备上播放」卡片关闭过的 bvid。
- 抖音精选响应缓存的“上次成功刷新时间”元数据。

不进入 RDB：

- `cacheDir/article-images/*.img`：可被系统清理的图片缓存。

## 数据库

- 文件：`com.dalton.dashiell.persistence.db`。
- 版本：`RdbStore.version = DATABASE_VERSION`（当前 2）；每行另有 `schema_version`。
- 安全级别：`relationalStore.SecurityLevel.S2`。
- 表：
  - `persistent_value`：单值 Key/Value，列 `value_key`、`value_namespace`、`value_type`、`value_text`、`value_integer`、`value_real`、`schema_version`、`first_stored_at`、`last_changed_at`、`migrated_from`。
  - `search_history`：`keyword` 主键、`sort_key`（`NOT NULL UNIQUE`）、时间戳、`schema_version`、`migrated_from`。
  - `rss_subscription`：`stable_id` 主键、`sort_key`（`NOT NULL UNIQUE`）、时间戳、`schema_version`、`migrated_from`。
  - `storage_meta`：schema 版本镜像、迁移开始/完成标记。
  - `legacy_migration_result`：一次性迁移每个条目的状态。

用户值不使用 JSON 列：布尔存 INTEGER 0/1，字符串存 TEXT，列表拆行，避免二次序列化。

## 列表顺序

两处列表（`search_history`、`rss_subscription`）的顺序就是**业务语义**：前者是"最近搜索在最前"，
后者是首页 RSS 的展示顺序。顺序只由 `sort_key` 一列表达，`ORDER BY sort_key ASC` 即展示顺序。

- **唯一即确定**：`sort_key` 带 `UNIQUE` 约束，schema 层不可能出现并列位置，读序因此永远确定，
  不需要靠 tiebreaker 兜底（查询里仍带上主键作为防御性次级排序）。
- **头插 = `MIN(sort_key) - 1`，尾插 = `MAX(sort_key) + 1`**：都是 O(1) 写，不再做全表 `+1` 位移。
  搜索历史每次写入从"最多 1000 行全表重写"降为一行。
- **只有相对顺序真的变化才整表重编号**：新编号从 `MAX+1` 起，逐条 UPDATE 不可能撞 UNIQUE；
  纯删除、纯首尾插入都完全不碰已有行的 key 和 `last_changed_at`。
- **RSS 中间插入**必须重编号（没有空隙可塞），这是唯一会写整表的情况；列表规模是十几个，代价可接受。
- **裁剪**：新增导致超过 1000 条时才裁剪，保留 `sort_key` 最小的 1000 条（`DELETE ... WHERE keyword NOT IN (SELECT ... ORDER BY sort_key, keyword LIMIT ?)`），
  不依赖位置连续，也不依赖 `OFFSET`。
- **去重**：`replaceOrder` 对重复 `stable_id` 按首次出现去重，避免主键冲突；空 id 直接忽略。

## Key 规范

单值 Key 格式：`<bundleName>.<feature>.<subject>.<value-semantics>`，例如：

- `com.dalton.dashiell.privacy-policy.user-consent.is-agreed`
- `com.dalton.dashiell.bilibili-account.has-logged-in-at-least-once`
- `com.dalton.dashiell.settings.personalized-recommendation.is-enabled`
- `com.dalton.dashiell.douyin-playback.loop-mode`
- `com.dalton.dashiell.douyin-feed-cache.last-successful-refresh-at`

列表行使用自然主键（`keyword` / `stable_id`），不生成哈希 Key。名称要能脱离代码读懂。

## 时间戳与版本

- `first_stored_at`：首次写入该逻辑记录的时间，更新时不变。
- `last_changed_at`：值/顺序真正变化时更新；相同值重复写入不更新。
- 时间统一 `Date#toISOString()`（UTC、毫秒）；排序/相等性判断不依赖时间戳。
- `RdbStore.version` 高于 `DATABASE_VERSION`：拒绝写入，记录日志。

## 代码入口

- `common/storage/AppDatabase.ets`：单例打开、schema、迁移。
- `common/storage/*Repository.ets`：业务读取/写入；事务边界在 Repository。
- `common/storage/LegacyPreferencesReader.ets`：唯一允许 import `preferences` / `PersistenceV2` 的生产文件，只读旧值。
- 业务代码不得直接 import `preferences` / `PersistenceV2`，也不得直接写 SQL；走 Repository。

## 绑定参数必须是普通数组

`relationalStore` 的 bindArgs 只认**普通数组**。ArkUI V2 里 `@Trace` 装饰的数组是代理对象，
直接原样传进去会在跨界时失效，但 JS 侧看起来一切正常：

```text
JS 侧：Array.isArray(proxy) === true，proxy.length === 1，JSON.stringify 正常
native：401 The values must be a BindArgs array
        或 bind args count(0) > numParameters(1)（事务里就是这个，整条事务回滚）
```

原因可以理解为两边的判定标准不同：`Array.isArray` 按 ECMAScript 语义会拆 Proxy，而 native 取数组长度、
校验参数类型用的是真实数组的内部槽，Proxy 没有。2026-10-27 在 Watch5 / API 23 实测：

| 传法 | 结果 |
|---|---|
| `replaceOrder(UI 状态里的 @Trace 数组)` | ❌ 401 / bind args 0 |
| `ids.slice()`、`Array.from(ids)`、`[...ids]`、循环 `push` | ✅ 全部正常绑定 |

所以：

- **业务代码不要绕开 `RdbSqlDatabase`** 直接调 `relationalStore`；绑定归一化只在这一处做。
- Repository/DAO 的 `string[]` 参数可以安全地接收 UI 状态数组——`RdbSqlDatabase.toBindArgs`
  会逐元素复制成普通数组。新增 DAO 时不要再写 `store.executeSql(sql, args)`。
- 真要手写 native 调用，先把数组复制成新数组；`.slice()` 在 V2 代理上返回的是新数组，够用。
- 回归用例：`entry/src/test/StorageBindArgs.test.ets`（真机 `aa test -s class storageBindArgs`），
  其中 `bindsTraceProxyArrayFromObservedV2` 守住"直接传代理数组也要能正确绑定"这个回归点。