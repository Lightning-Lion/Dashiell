/**
 * RDB 持久化使用的长 Key。
 *
 * 命名规则：<bundleName>.<feature>.<subject>.<value-semantics>
 * - 单值记录用 persistent_value.value_key；
 * - 列表记录用自然主键（keyword / stable_id），不生成哈希 Key；
 * - 版本号放在记录的 schema_version 字段，不放进 Key。
 */
export class StorageNamespaces {
  static readonly SETTING: string = 'setting';
  static readonly STATE: string = 'state';
}

export class StorageKeys {
  static readonly PRIVACY_POLICY_AGREED: string =
    'com.dalton.dashiell.privacy-policy.user-consent.is-agreed';
  static readonly BILI_LOGGED_IN_AT_LEAST_ONCE: string =
    'com.dalton.dashiell.bilibili-account.has-logged-in-at-least-once';
  static readonly PERSONALIZED_RECOMMENDATION_ENABLED: string =
    'com.dalton.dashiell.settings.personalized-recommendation.is-enabled';
  static readonly DOUYIN_LOOP_MODE: string =
    'com.dalton.dashiell.douyin-playback.loop-mode';
  static readonly DOUYIN_FEED_CACHE_LAST_REFRESH: string =
    'com.dalton.dashiell.douyin-feed-cache.last-successful-refresh-at';
  static readonly BILI_HOME_RESUME_CARD_DISMISSED_BVID: string =
    'com.dalton.dashiell.bilibili-home.resume-card.dismissed-bvid';

  static readonly STORAGE_SCHEMA_VERSION: string =
    'com.dalton.dashiell.storage.schema-version';
  static readonly STORAGE_CREATED_AT: string =
    'com.dalton.dashiell.storage.created-at';

  static readonly LEGACY_MIGRATION_ID: string =
    'com.dalton.dashiell.storage-migration.legacy-kv-to-rdb.v1';
  static readonly LEGACY_MIGRATION_COMPLETED_AT: string =
    'com.dalton.dashiell.storage-migration.legacy-kv-to-rdb.v1.completed-at';
  static readonly LEGACY_MIGRATION_STARTED_AT: string =
    'com.dalton.dashiell.storage-migration.legacy-kv-to-rdb.v1.started-at';
}

/**
 * cbb63c9 及之前已上线代码使用的旧 Key。
 * 只允许 LegacyPreferencesReader 引用；迁移完成后业务代码不再读写这些 Key。
 */
export class LegacyStorageKeys {
  static readonly PRIVACY_STORE: string = '979b7a49-a5c8-4634-8042-b9bb85da7d69';
  static readonly PRIVACY_KEY: string = 'd74e8815-777a-4a5e-b602-c5519c63d87e';

  static readonly BILI_ACCOUNT_STORE: string = '7943490c-3d97-419c-90e7-a779e1ac2248';
  static readonly BILI_ACCOUNT_KEY: string = '024e6861-5fcf-4d44-a3e3-ff7b704e13f3';

  static readonly SEARCH_HISTORY_STORE: string = 'searchHistoriesStorageIdV1';
  static readonly SEARCH_HISTORY_KEY: string = 'searchHistoriesStorageIdV1';

  static readonly RSS_STORE: string = 'fa470bf5-94e9-480b-bee8-dfc63905c45c';
  static readonly RSS_KEY: string = '150b85e6-f63b-4d5e-b0a6-3e4a076be0f9';

  static readonly PERSONALIZED_STORE: string = '1ee5f7aa-9d4b-410e-bb46-f6beab3f5860';
  static readonly PERSONALIZED_KEY: string = '0673f06f-4e63-45f2-989a-74c92a35c57d';

  static readonly DOUYIN_CACHE_PERSISTENCE_V2_KEY: string = 'c1e9de606ba148a0b12e';
}

export class MigrationEntryIds {
  static readonly PRIVACY: string = StorageKeys.LEGACY_MIGRATION_ID + '.privacy-consent';
  static readonly LOGGED_IN: string =
    StorageKeys.LEGACY_MIGRATION_ID + '.has-logged-in-at-least-once';
  static readonly SEARCH_HISTORY: string =
    StorageKeys.LEGACY_MIGRATION_ID + '.bilibili-search-history';
  static readonly RSS_SOURCES: string =
    StorageKeys.LEGACY_MIGRATION_ID + '.rss-subscriptions';
  static readonly PERSONALIZED: string =
    StorageKeys.LEGACY_MIGRATION_ID + '.personalized-recommendation';
  static readonly DOUYIN_CACHE: string =
    StorageKeys.LEGACY_MIGRATION_ID + '.douyin-feed-cache-timestamp';
}
