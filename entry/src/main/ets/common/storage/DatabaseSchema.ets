/** RDB 文件名：稳定文件名，版本由 RdbStore.version 和行级 schema_version 管理。 */
export const DATABASE_NAME: string = 'com.dalton.dashiell.persistence.db';
/**
 * v1 版本之前从未上线，所以 v1 → v2 直接重建整库，旧数据仍在 legacy KV 里、由一次性迁移补回，见 AppDatabase。
 */
export const DATABASE_VERSION: number = 2;

export class StorageTables {
  static readonly PERSISTENT_VALUE: string = 'persistent_value';
  static readonly SEARCH_HISTORY: string = 'search_history';
  static readonly RSS_SUBSCRIPTION: string = 'rss_subscription';
  static readonly STORAGE_META: string = 'storage_meta';
  static readonly LEGACY_MIGRATION_RESULT: string = 'legacy_migration_result';
}

export class PersistentValueColumns {
  static readonly KEY: string = 'value_key';
  static readonly NAMESPACE: string = 'value_namespace';
  static readonly TYPE: string = 'value_type';
  static readonly TEXT: string = 'value_text';
  static readonly INTEGER: string = 'value_integer';
  static readonly REAL: string = 'value_real';
  static readonly SCHEMA_VERSION: string = 'schema_version';
  static readonly FIRST_STORED_AT: string = 'first_stored_at';
  static readonly LAST_CHANGED_AT: string = 'last_changed_at';
  static readonly MIGRATED_FROM: string = 'migrated_from';
}

export class SearchHistoryColumns {
  static readonly KEYWORD: string = 'keyword';
  // 升序即展示顺序；只要求唯一，不要求连续（头插 = MIN-1，尾插 = MAX+1）。
  static readonly SORT_KEY: string = 'sort_key';
  static readonly SCHEMA_VERSION: string = 'schema_version';
  static readonly FIRST_STORED_AT: string = 'first_stored_at';
  static readonly LAST_CHANGED_AT: string = 'last_changed_at';
  static readonly MIGRATED_FROM: string = 'migrated_from';
}

export class RssSubscriptionColumns {
  static readonly STABLE_ID: string = 'stable_id';
  // 升序即首页展示顺序；UNIQUE 由 schema 保证，重排时整表重新编号。
  static readonly SORT_KEY: string = 'sort_key';
  static readonly SCHEMA_VERSION: string = 'schema_version';
  static readonly FIRST_STORED_AT: string = 'first_stored_at';
  static readonly LAST_CHANGED_AT: string = 'last_changed_at';
  static readonly MIGRATED_FROM: string = 'migrated_from';
}

export class StorageMetaColumns {
  static readonly KEY: string = 'meta_key';
  static readonly VALUE: string = 'meta_value';
  static readonly SCHEMA_VERSION: string = 'schema_version';
  static readonly FIRST_STORED_AT: string = 'first_stored_at';
  static readonly LAST_CHANGED_AT: string = 'last_changed_at';
}

export class LegacyMigrationResultColumns {
  static readonly MIGRATION_ID: string = 'migration_id';
  static readonly ENTRY_ID: string = 'entry_id';
  static readonly STATUS: string = 'status';
  static readonly SOURCE_STORE: string = 'source_store';
  static readonly SOURCE_KEY: string = 'source_key';
  static readonly SCHEMA_VERSION: string = 'schema_version';
  static readonly RECORDED_AT: string = 'recorded_at';
}

/**
 * 每个表都带 schema_version；单值/列表行还带 first_stored_at、last_changed_at。
 * 不使用 JSON 列承载用户值，避免二次序列化。
 *
 * 列表表（search_history / rss_subscription）的顺序模型：
 * - 只有 sort_key 一列表达顺序，`ORDER BY sort_key ASC` 就是展示顺序；
 * - sort_key 有 UNIQUE 约束，并列位置在 schema 层就不可能存在（读序永远确定）；
 * - 头部插入 = MIN(sort_key) - 1，尾部插入 = MAX(sort_key) + 1，两者都是 O(1) 写；
 * - 相对顺序真的变化时才整表重新编号，新编号从 MAX+1 起，不会撞旧值；
 * - 因此不存在"全表 +1"位移，搜索历史每次写入不再随条数放大。
 */
/** 仅用于 v1 → v2 的预发布重置（v1 从未上线）；上线后不要再走这个路径。 */
export const DROP_SCHEMA_SQL: string[] = [
  `DROP TABLE IF EXISTS ${StorageTables.SEARCH_HISTORY}`,
  `DROP TABLE IF EXISTS ${StorageTables.RSS_SUBSCRIPTION}`,
  `DROP TABLE IF EXISTS ${StorageTables.PERSISTENT_VALUE}`,
  `DROP TABLE IF EXISTS ${StorageTables.STORAGE_META}`,
  `DROP TABLE IF EXISTS ${StorageTables.LEGACY_MIGRATION_RESULT}`
];

export const CREATE_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${StorageTables.PERSISTENT_VALUE} (
    ${PersistentValueColumns.KEY} TEXT PRIMARY KEY NOT NULL,
    ${PersistentValueColumns.NAMESPACE} TEXT NOT NULL CHECK (${PersistentValueColumns.NAMESPACE} IN ('setting', 'state')),
    ${PersistentValueColumns.TYPE} TEXT NOT NULL CHECK (${PersistentValueColumns.TYPE} IN ('boolean', 'string', 'integer', 'real')),
    ${PersistentValueColumns.TEXT} TEXT,
    ${PersistentValueColumns.INTEGER} INTEGER,
    ${PersistentValueColumns.REAL} REAL,
    ${PersistentValueColumns.SCHEMA_VERSION} INTEGER NOT NULL CHECK (${PersistentValueColumns.SCHEMA_VERSION} > 0),
    ${PersistentValueColumns.FIRST_STORED_AT} TEXT NOT NULL,
    ${PersistentValueColumns.LAST_CHANGED_AT} TEXT NOT NULL,
    ${PersistentValueColumns.MIGRATED_FROM} TEXT,
    CHECK (
      (${PersistentValueColumns.TYPE} = 'boolean' AND ${PersistentValueColumns.INTEGER} IS NOT NULL) OR
      (${PersistentValueColumns.TYPE} = 'string' AND ${PersistentValueColumns.TEXT} IS NOT NULL) OR
      (${PersistentValueColumns.TYPE} = 'integer' AND ${PersistentValueColumns.INTEGER} IS NOT NULL) OR
      (${PersistentValueColumns.TYPE} = 'real' AND ${PersistentValueColumns.REAL} IS NOT NULL)
    )
  )`,
  `CREATE TABLE IF NOT EXISTS ${StorageTables.SEARCH_HISTORY} (
    ${SearchHistoryColumns.KEYWORD} TEXT PRIMARY KEY NOT NULL,
    ${SearchHistoryColumns.SORT_KEY} INTEGER NOT NULL UNIQUE,
    ${SearchHistoryColumns.SCHEMA_VERSION} INTEGER NOT NULL CHECK (${SearchHistoryColumns.SCHEMA_VERSION} > 0),
    ${SearchHistoryColumns.FIRST_STORED_AT} TEXT NOT NULL,
    ${SearchHistoryColumns.LAST_CHANGED_AT} TEXT NOT NULL,
    ${SearchHistoryColumns.MIGRATED_FROM} TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS ${StorageTables.RSS_SUBSCRIPTION} (
    ${RssSubscriptionColumns.STABLE_ID} TEXT PRIMARY KEY NOT NULL,
    ${RssSubscriptionColumns.SORT_KEY} INTEGER NOT NULL UNIQUE,
    ${RssSubscriptionColumns.SCHEMA_VERSION} INTEGER NOT NULL CHECK (${RssSubscriptionColumns.SCHEMA_VERSION} > 0),
    ${RssSubscriptionColumns.FIRST_STORED_AT} TEXT NOT NULL,
    ${RssSubscriptionColumns.LAST_CHANGED_AT} TEXT NOT NULL,
    ${RssSubscriptionColumns.MIGRATED_FROM} TEXT
  )`,
  `CREATE TABLE IF NOT EXISTS ${StorageTables.STORAGE_META} (
    ${StorageMetaColumns.KEY} TEXT PRIMARY KEY NOT NULL,
    ${StorageMetaColumns.VALUE} TEXT NOT NULL,
    ${StorageMetaColumns.SCHEMA_VERSION} INTEGER NOT NULL CHECK (${StorageMetaColumns.SCHEMA_VERSION} > 0),
    ${StorageMetaColumns.FIRST_STORED_AT} TEXT NOT NULL,
    ${StorageMetaColumns.LAST_CHANGED_AT} TEXT NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS ${StorageTables.LEGACY_MIGRATION_RESULT} (
    ${LegacyMigrationResultColumns.MIGRATION_ID} TEXT NOT NULL,
    ${LegacyMigrationResultColumns.ENTRY_ID} TEXT NOT NULL,
    ${LegacyMigrationResultColumns.STATUS} TEXT NOT NULL,
    ${LegacyMigrationResultColumns.SOURCE_STORE} TEXT NOT NULL,
    ${LegacyMigrationResultColumns.SOURCE_KEY} TEXT NOT NULL,
    ${LegacyMigrationResultColumns.SCHEMA_VERSION} INTEGER NOT NULL,
    ${LegacyMigrationResultColumns.RECORDED_AT} TEXT NOT NULL,
    PRIMARY KEY (${LegacyMigrationResultColumns.MIGRATION_ID}, ${LegacyMigrationResultColumns.ENTRY_ID})
  )`
];
