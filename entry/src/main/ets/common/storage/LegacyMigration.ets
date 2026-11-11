import { logTag } from '../printLog';
import { PersistentValueDao } from './PersistentValueDao';
import { RssSubscriptionDao } from './RssSubscriptionDao';
import { SearchHistoryDao } from './SearchHistoryDao';
import { SqlDatabase } from './SqlDatabase';
import { StorageMetaDao } from './StorageMetaDao';
import { LegacyStorageKeys, MigrationEntryIds, StorageKeys, StorageNamespaces } from './StorageKeys';
import { StorageClock, StorageTime } from './StorageTime';
import {
  LegacyBooleanResult,
  LegacyPersonalizedResult,
  LegacyReadStatus,
  LegacySnapshotReader,
  LegacyStringListResult,
  LegacyTimestampResult
} from './LegacySnapshot';

export enum MigrationEntryStatus {
  MIGRATED = 'migrated',
  MISSING = 'missing',
  INVALID = 'invalid',
  SKIPPED_EXISTING = 'skipped-existing',
  FAILED = 'failed'
}

export interface MigrationEntryResult {
  entryId: string;
  status: MigrationEntryStatus;
  sourceStore: string;
  sourceKey: string;
  critical: boolean;
}

export interface MigrationReport {
  complete: boolean;
  alreadyComplete: boolean;
  results: MigrationEntryResult[];
  error: string;
}

class MigrationAbortError extends Error {
  readonly entryId: string;

  constructor(entryId: string) {
    super('critical legacy migration entry failed: ' + entryId);
    this.name = 'MigrationAbortError';
    this.entryId = entryId;
  }
}

/**
 * 一次性迁移：只处理 cbb63c9 及之前已上线的 6 组数据。
 * 旧 preferences/PersistenceV2 只读，不删除；成功 commit 并回读标记后才算完成。
 */
export class LegacyMigration {
  static async runOnce(db: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock): Promise<MigrationReport> {
    const meta = new StorageMetaDao(db, clock);
    try {
      if (await meta.hasCompletedMarker(StorageKeys.LEGACY_MIGRATION_COMPLETED_AT)) {
        return { complete: true, alreadyComplete: true, results: [], error: '' };
      }
    } catch (error) {
      return { complete: false, alreadyComplete: false, results: [], error: LegacyMigration.describe(error) };
    }

    const results: MigrationEntryResult[] = [];
    try {
      await db.transaction(async (tx: SqlDatabase): Promise<void> => {
        const txMeta = new StorageMetaDao(tx, clock);
        await txMeta.set(StorageKeys.LEGACY_MIGRATION_STARTED_AT, clock.nowIso());

        await LegacyMigration.migratePrivacy(tx, reader, clock, results);
        await LegacyMigration.migrateLoggedIn(tx, reader, clock, results);
        await LegacyMigration.migrateSearchHistory(tx, reader, clock, results);
        await LegacyMigration.migrateRssSources(tx, reader, clock, results);
        await LegacyMigration.migratePersonalized(tx, reader, clock, results);
        await LegacyMigration.migrateDouyinCache(tx, reader, clock, results);

        const failed = LegacyMigration.firstCriticalFailure(results);
        if (failed !== '') {
          throw new MigrationAbortError(failed);
        }
        const completedAt = clock.nowIso();
        for (const result of results) {
          await txMeta.recordMigrationResult(StorageKeys.LEGACY_MIGRATION_ID, result.entryId,
            result.status, result.sourceStore, result.sourceKey, completedAt);
        }
        await txMeta.set(StorageKeys.LEGACY_MIGRATION_COMPLETED_AT, completedAt);
      });
    } catch (error) {
      const message = LegacyMigration.describe(error);
      console.debug(logTag, 'legacy migration aborted: ' + message);
      return { complete: false, alreadyComplete: false, results: results, error: message };
    }

    try {
      const complete = await meta.hasCompletedMarker(StorageKeys.LEGACY_MIGRATION_COMPLETED_AT);
      if (!complete) {
        console.debug(logTag, 'legacy migration committed but marker verification failed');
        return { complete: false, alreadyComplete: false, results: results, error: 'marker verification failed' };
      }
    } catch (error) {
      return { complete: false, alreadyComplete: false, results: results, error: LegacyMigration.describe(error) };
    }

    console.debug(logTag, 'legacy migration completed entries=' + results.length);
    return { complete: true, alreadyComplete: false, results: results, error: '' };
  }

  private static async migratePrivacy(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = LegacyStorageKeys.PRIVACY_STORE;
    const sourceKey = LegacyStorageKeys.PRIVACY_KEY;
    const migratedFrom = LegacyMigration.preferencesRef(sourceStore, sourceKey);
    try {
      const values = new PersistentValueDao(tx, clock);
      if ((await values.getRecord(StorageKeys.PRIVACY_POLICY_AGREED)) !== null) {
        LegacyMigration.push(results, MigrationEntryIds.PRIVACY, MigrationEntryStatus.SKIPPED_EXISTING,
          sourceStore, sourceKey, true);
        return;
      }
      const legacy: LegacyBooleanResult = await reader.readPrivacyConsent();
      await LegacyMigration.migrateBoolean(values, StorageKeys.PRIVACY_POLICY_AGREED,
        StorageNamespaces.SETTING, legacy, clock, results, MigrationEntryIds.PRIVACY,
        sourceStore, sourceKey, migratedFrom, true);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.PRIVACY, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, true);
      console.debug(logTag, 'migrate privacy failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migrateLoggedIn(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = LegacyStorageKeys.BILI_ACCOUNT_STORE;
    const sourceKey = LegacyStorageKeys.BILI_ACCOUNT_KEY;
    const migratedFrom = LegacyMigration.preferencesRef(sourceStore, sourceKey);
    try {
      const values = new PersistentValueDao(tx, clock);
      if ((await values.getRecord(StorageKeys.BILI_LOGGED_IN_AT_LEAST_ONCE)) !== null) {
        LegacyMigration.push(results, MigrationEntryIds.LOGGED_IN, MigrationEntryStatus.SKIPPED_EXISTING,
          sourceStore, sourceKey, true);
        return;
      }
      const legacy: LegacyBooleanResult = await reader.readLoggedInAtLeastOnce();
      await LegacyMigration.migrateBoolean(values, StorageKeys.BILI_LOGGED_IN_AT_LEAST_ONCE,
        StorageNamespaces.SETTING, legacy, clock, results, MigrationEntryIds.LOGGED_IN,
        sourceStore, sourceKey, migratedFrom, true);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.LOGGED_IN, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, true);
      console.debug(logTag, 'migrate logged-in failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migrateSearchHistory(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = LegacyStorageKeys.SEARCH_HISTORY_STORE;
    const sourceKey = LegacyStorageKeys.SEARCH_HISTORY_KEY;
    const migratedFrom = LegacyMigration.preferencesRef(sourceStore, sourceKey);
    try {
      const dao = new SearchHistoryDao(tx, clock);
      if ((await dao.count()) > 0) {
        LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY,
          MigrationEntryStatus.SKIPPED_EXISTING, sourceStore, sourceKey, true);
        return;
      }
      const legacy: LegacyStringListResult = await reader.readSearchHistory();
      if (legacy.status === LegacyReadStatus.MISSING) {
        LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY, MigrationEntryStatus.MISSING,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.ERROR) {
        LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY, MigrationEntryStatus.FAILED,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.INVALID || legacy.values === null) {
        LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY, MigrationEntryStatus.INVALID,
          sourceStore, sourceKey, true);
        return;
      }
      const inserted = await dao.insertMigrated(legacy.values, clock.nowIso(), migratedFrom);
      LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY,
        inserted ? MigrationEntryStatus.MIGRATED : MigrationEntryStatus.SKIPPED_EXISTING,
        sourceStore, sourceKey, true);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.SEARCH_HISTORY, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, true);
      console.debug(logTag, 'migrate search history failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migrateRssSources(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = LegacyStorageKeys.RSS_STORE;
    const sourceKey = LegacyStorageKeys.RSS_KEY;
    const migratedFrom = LegacyMigration.preferencesRef(sourceStore, sourceKey);
    try {
      const dao = new RssSubscriptionDao(tx, clock);
      if ((await dao.count()) > 0) {
        LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES,
          MigrationEntryStatus.SKIPPED_EXISTING, sourceStore, sourceKey, true);
        return;
      }
      const legacy: LegacyStringListResult = await reader.readRssSources();
      if (legacy.status === LegacyReadStatus.MISSING) {
        LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES, MigrationEntryStatus.MISSING,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.ERROR) {
        LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES, MigrationEntryStatus.FAILED,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.INVALID || legacy.values === null) {
        LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES, MigrationEntryStatus.INVALID,
          sourceStore, sourceKey, true);
        return;
      }
      const inserted = await dao.insertMigrated(legacy.values, clock.nowIso(), migratedFrom);
      LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES,
        inserted ? MigrationEntryStatus.MIGRATED : MigrationEntryStatus.SKIPPED_EXISTING,
        sourceStore, sourceKey, true);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.RSS_SOURCES, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, true);
      console.debug(logTag, 'migrate rss sources failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migratePersonalized(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = LegacyStorageKeys.PERSONALIZED_STORE;
    const sourceKey = LegacyStorageKeys.PERSONALIZED_KEY;
    const migratedFrom = LegacyMigration.preferencesRef(sourceStore, sourceKey);
    try {
      const values = new PersistentValueDao(tx, clock);
      if ((await values.getRecord(StorageKeys.PERSONALIZED_RECOMMENDATION_ENABLED)) !== null) {
        LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED,
          MigrationEntryStatus.SKIPPED_EXISTING, sourceStore, sourceKey, true);
        return;
      }
      const legacy: LegacyPersonalizedResult = await reader.readPersonalized();
      if (legacy.status === LegacyReadStatus.MISSING) {
        LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED, MigrationEntryStatus.MISSING,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.ERROR) {
        LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED, MigrationEntryStatus.FAILED,
          sourceStore, sourceKey, true);
        return;
      }
      if (legacy.status === LegacyReadStatus.INVALID || legacy.enabled === null) {
        LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED, MigrationEntryStatus.INVALID,
          sourceStore, sourceKey, true);
        return;
      }
      const now = clock.nowIso();
      const legacyIso = StorageTime.clampToNow(legacy.lastChangedAt, now);
      const inserted = await values.insertMigratedBoolean(StorageKeys.PERSONALIZED_RECOMMENDATION_ENABLED,
        StorageNamespaces.SETTING, legacy.enabled, legacyIso, legacyIso, migratedFrom);
      LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED,
        inserted ? MigrationEntryStatus.MIGRATED : MigrationEntryStatus.SKIPPED_EXISTING,
        sourceStore, sourceKey, true);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.PERSONALIZED, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, true);
      console.debug(logTag, 'migrate personalized failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migrateDouyinCache(tx: SqlDatabase, reader: LegacySnapshotReader,
    clock: StorageClock, results: MigrationEntryResult[]): Promise<void> {
    const sourceStore = 'persistence-v2';
    const sourceKey = LegacyStorageKeys.DOUYIN_CACHE_PERSISTENCE_V2_KEY;
    const migratedFrom = sourceStore + ':' + sourceKey;
    try {
      const values = new PersistentValueDao(tx, clock);
      if ((await values.getRecord(StorageKeys.DOUYIN_FEED_CACHE_LAST_REFRESH)) !== null) {
        LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE,
          MigrationEntryStatus.SKIPPED_EXISTING, sourceStore, sourceKey, false);
        return;
      }
      const legacy: LegacyTimestampResult = await reader.readDouyinCacheTimestamp();
      if (legacy.status === LegacyReadStatus.MISSING) {
        LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE, MigrationEntryStatus.MISSING,
          sourceStore, sourceKey, false);
        return;
      }
      if (legacy.status === LegacyReadStatus.ERROR) {
        LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE, MigrationEntryStatus.FAILED,
          sourceStore, sourceKey, false);
        return;
      }
      if (legacy.status === LegacyReadStatus.INVALID || legacy.timestamp === null) {
        LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE, MigrationEntryStatus.INVALID,
          sourceStore, sourceKey, false);
        return;
      }
      const now = clock.nowIso();
      const legacyIso = StorageTime.clampToNow(legacy.timestamp, now);
      const inserted = await values.insertMigratedString(StorageKeys.DOUYIN_FEED_CACHE_LAST_REFRESH,
        StorageNamespaces.STATE, legacyIso, legacyIso, legacyIso, migratedFrom);
      LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE,
        inserted ? MigrationEntryStatus.MIGRATED : MigrationEntryStatus.SKIPPED_EXISTING,
        sourceStore, sourceKey, false);
    } catch (error) {
      LegacyMigration.push(results, MigrationEntryIds.DOUYIN_CACHE, MigrationEntryStatus.FAILED,
        sourceStore, sourceKey, false);
      console.debug(logTag, 'migrate douyin cache failed: ' + LegacyMigration.describe(error));
    }
  }

  private static async migrateBoolean(values: PersistentValueDao, key: string, namespace: string,
    legacy: LegacyBooleanResult, clock: StorageClock, results: MigrationEntryResult[],
    entryId: string, sourceStore: string, sourceKey: string, migratedFrom: string,
    critical: boolean): Promise<void> {
    if (legacy.status === LegacyReadStatus.MISSING) {
      LegacyMigration.push(results, entryId, MigrationEntryStatus.MISSING, sourceStore, sourceKey, critical);
      return;
    }
    if (legacy.status === LegacyReadStatus.ERROR) {
      LegacyMigration.push(results, entryId, MigrationEntryStatus.FAILED, sourceStore, sourceKey, critical);
      return;
    }
    if (legacy.status === LegacyReadStatus.INVALID || legacy.value === null) {
      LegacyMigration.push(results, entryId, MigrationEntryStatus.INVALID, sourceStore, sourceKey, critical);
      return;
    }
    const now = clock.nowIso();
    const inserted = await values.insertMigratedBoolean(key, namespace, legacy.value, now, now, migratedFrom);
    LegacyMigration.push(results, entryId,
      inserted ? MigrationEntryStatus.MIGRATED : MigrationEntryStatus.SKIPPED_EXISTING,
      sourceStore, sourceKey, critical);
  }

  private static preferencesRef(store: string, key: string): string {
    return 'preferences:' + store + '/' + key;
  }

  private static push(results: MigrationEntryResult[], entryId: string, status: MigrationEntryStatus,
    sourceStore: string, sourceKey: string, critical: boolean): void {
    results.push({
      entryId: entryId,
      status: status,
      sourceStore: sourceStore,
      sourceKey: sourceKey,
      critical: critical
    });
  }

  private static firstCriticalFailure(results: MigrationEntryResult[]): string {
    for (const result of results) {
      if (result.critical && result.status === MigrationEntryStatus.FAILED) {
        return result.entryId;
      }
    }
    return '';
  }

  private static describe(error: Object): string {
    const message = (error as Error).message;
    return message === undefined ? 'unknown' : message;
  }
}
