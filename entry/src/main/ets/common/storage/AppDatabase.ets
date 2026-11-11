import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CREATE_SCHEMA_SQL, DATABASE_NAME, DATABASE_VERSION, DROP_SCHEMA_SQL } from './DatabaseSchema';
import { LegacyMigration } from './LegacyMigration';
import { LegacyPreferencesReader } from './LegacyPreferencesReader';
import { PersistentValueRepository } from './PersistentValueRepository';
import { RdbSqlDatabase } from './RdbSqlDatabase';
import { RssSubscriptionRepository } from './RssSubscriptionRepository';
import { SearchHistoryRepository } from './SearchHistoryRepository';
import { SqlDatabase, UnsupportedStorageVersionError } from './SqlDatabase';
import { StorageKeys } from './StorageKeys';
import { StorageMetaDao } from './StorageMetaDao';
import { SystemStorageClock } from './StorageTime';
import { LogEvents } from '../../utils/log/LogEvents.generated';

const DB_CONFIG: relationalStore.StoreConfig = {
  name: DATABASE_NAME,
  securityLevel: relationalStore.SecurityLevel.S2
};

/**
 * RDB 单例入口。
 * - 打开数据库、确保 schema 版本；
 * - 执行一次旧 preferences/PersistenceV2 迁移；
 * - 暴露各 Repository。
 *
 * 迁移失败不阻止 App 启动：标记不写、旧数据保留、下次启动重试。
 */
export class AppDatabase {
  readonly values: PersistentValueRepository;
  readonly searchHistory: SearchHistoryRepository;
  readonly rssSubscriptions: RssSubscriptionRepository;

  private migrationCompleteFlag: boolean = false;

  private static instance: AppDatabase | null = null;
  private static opening: Promise<AppDatabase> | null = null;

  private constructor(sqlDb: SqlDatabase) {
    this.values = new PersistentValueRepository(sqlDb);
    this.searchHistory = new SearchHistoryRepository(sqlDb);
    this.rssSubscriptions = new RssSubscriptionRepository(sqlDb);
  }

  static open(context: common.Context): Promise<AppDatabase> {
    if (AppDatabase.instance !== null) {
      return Promise.resolve(AppDatabase.instance);
    }
    if (AppDatabase.opening === null) {
      AppDatabase.opening = AppDatabase.create(context).catch((error: Object) => {
        AppDatabase.opening = null;
        throw error as Error;
      });
    }
    return AppDatabase.opening;
  }

  get migrationComplete(): boolean {
    return this.migrationCompleteFlag;
  }

  private static async create(context: common.Context): Promise<AppDatabase> {
    // RDB 是 app 级目录；旧 preferences 是 hap 级目录（haps/entry/preferences），
    // 必须用启动时的 UIAbility context 读取，不能用 getApplicationContext()。
    const appContext: common.Context = context.getApplicationContext();
    const rdb: relationalStore.RdbStore = await relationalStore.getRdbStore(appContext, DB_CONFIG);
    const sqlDb: SqlDatabase = new RdbSqlDatabase(rdb);
    await AppDatabase.ensureSchema(rdb, sqlDb);
    const db = new AppDatabase(sqlDb);
    try {
      const report = await LegacyMigration.runOnce(sqlDb, new LegacyPreferencesReader(context),
        new SystemStorageClock());
      db.migrationCompleteFlag = report.complete;
      if (!report.complete) {
        LogEvents.dbMigrationIncomplete({ reason: report.error });
      }
    } catch (error) {
      db.migrationCompleteFlag = false;
      LogEvents.dbMigrationFailed(error);
    }
    AppDatabase.instance = db;
    return db;
  }

  private static async ensureSchema(rdb: relationalStore.RdbStore, sqlDb: SqlDatabase): Promise<void> {
    const currentVersion: number = rdb.version;
    if (currentVersion > DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'database version ' + currentVersion + ' is newer than app version ' + DATABASE_VERSION);
    }
    if (currentVersion === 1 && DATABASE_VERSION > 1) {
      // v1 从未上线，这里直接重建整库。
      // 用户数据仍在 legacy KV 里（迁移只读不删），随后的一次性迁移会重新写入。
      LogEvents.dbSchemaReset({ from: currentVersion, to: DATABASE_VERSION });
      for (const statement of DROP_SCHEMA_SQL) {
        await sqlDb.execute(statement);
      }
    }
    for (const statement of CREATE_SCHEMA_SQL) {
      await sqlDb.execute(statement);
    }
    if (currentVersion < DATABASE_VERSION) {
      rdb.version = DATABASE_VERSION;
    }
    const meta = new StorageMetaDao(sqlDb);
    await meta.ensure(StorageKeys.STORAGE_SCHEMA_VERSION, String(DATABASE_VERSION));
    await meta.ensure(StorageKeys.STORAGE_CREATED_AT, new SystemStorageClock().nowIso());
  }
}
