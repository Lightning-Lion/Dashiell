import {
  DATABASE_VERSION,
  LegacyMigrationResultColumns,
  StorageMetaColumns
} from './DatabaseSchema';
import {
  SqlDatabase,
  SqlRow,
  UnsupportedStorageVersionError,
  requiredNumber,
  requiredString
} from './SqlDatabase';
import { StorageClock, StorageTime, SystemStorageClock } from './StorageTime';

const TABLE: string = 'storage_meta';
const RESULT_TABLE: string = 'legacy_migration_result';

const SELECT_SQL: string =
  `SELECT ${StorageMetaColumns.VALUE}, ${StorageMetaColumns.SCHEMA_VERSION}, ` +
  `${StorageMetaColumns.FIRST_STORED_AT}, ${StorageMetaColumns.LAST_CHANGED_AT} ` +
  `FROM ${TABLE} WHERE ${StorageMetaColumns.KEY} = ?`;
const INSERT_SQL: string =
  `INSERT INTO ${TABLE} (${StorageMetaColumns.KEY}, ${StorageMetaColumns.VALUE}, ` +
  `${StorageMetaColumns.SCHEMA_VERSION}, ${StorageMetaColumns.FIRST_STORED_AT}, ` +
  `${StorageMetaColumns.LAST_CHANGED_AT}) VALUES (?, ?, ?, ?, ?)`;
const UPDATE_SQL: string =
  `UPDATE ${TABLE} SET ${StorageMetaColumns.VALUE} = ?, ${StorageMetaColumns.SCHEMA_VERSION} = ?, ` +
  `${StorageMetaColumns.LAST_CHANGED_AT} = ? WHERE ${StorageMetaColumns.KEY} = ?`;

const RECORD_RESULT_SQL: string =
  `INSERT OR REPLACE INTO ${RESULT_TABLE} (` +
  `${LegacyMigrationResultColumns.MIGRATION_ID}, ${LegacyMigrationResultColumns.ENTRY_ID}, ` +
  `${LegacyMigrationResultColumns.STATUS}, ${LegacyMigrationResultColumns.SOURCE_STORE}, ` +
  `${LegacyMigrationResultColumns.SOURCE_KEY}, ${LegacyMigrationResultColumns.SCHEMA_VERSION}, ` +
  `${LegacyMigrationResultColumns.RECORDED_AT}) VALUES (?, ?, ?, ?, ?, ?, ?)`;
const SELECT_RESULTS_SQL: string =
  `SELECT ${LegacyMigrationResultColumns.ENTRY_ID}, ${LegacyMigrationResultColumns.STATUS}, ` +
  `${LegacyMigrationResultColumns.SOURCE_STORE}, ${LegacyMigrationResultColumns.SOURCE_KEY}, ` +
  `${LegacyMigrationResultColumns.SCHEMA_VERSION}, ${LegacyMigrationResultColumns.RECORDED_AT} ` +
  `FROM ${RESULT_TABLE} WHERE ${LegacyMigrationResultColumns.MIGRATION_ID} = ? ` +
  `ORDER BY ${LegacyMigrationResultColumns.ENTRY_ID} ASC`;

export interface StorageMetaRecord {
  value: string;
  schemaVersion: number;
  firstStoredAt: string;
  lastChangedAt: string;
}

export interface LegacyMigrationResultRecord {
  entryId: string;
  status: string;
  sourceStore: string;
  sourceKey: string;
  schemaVersion: number;
  recordedAt: string;
}

/** storage_meta / legacy_migration_result 的低层读写。 */
export class StorageMetaDao {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getRecord(key: string): Promise<StorageMetaRecord | null> {
    const rows: SqlRow[] = await this.db.query(SELECT_SQL, [key]);
    if (rows.length === 0) {
      return null;
    }
    const record: StorageMetaRecord = {
      value: requiredString(rows[0], StorageMetaColumns.VALUE),
      schemaVersion: requiredNumber(rows[0], StorageMetaColumns.SCHEMA_VERSION),
      firstStoredAt: requiredString(rows[0], StorageMetaColumns.FIRST_STORED_AT),
      lastChangedAt: requiredString(rows[0], StorageMetaColumns.LAST_CHANGED_AT)
    };
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'storage_meta schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
    return record;
  }

  async get(key: string): Promise<string | null> {
    const record = await this.getRecord(key);
    return record === null ? null : record.value;
  }

  async set(key: string, value: string): Promise<boolean> {
    const existing = await this.getRecord(key);
    const now = this.clock.nowIso();
    if (existing === null) {
      await this.db.execute(INSERT_SQL, [key, value, DATABASE_VERSION, now, now]);
      return true;
    }
    if (existing.value === value) {
      return false;
    }
    const lastChangedAt = StorageTime.clampChangedAt(existing.firstStoredAt, now);
    await this.db.execute(UPDATE_SQL, [value, DATABASE_VERSION, lastChangedAt, key]);
    return true;
  }

  async ensure(key: string, value: string): Promise<void> {
    const existing = await this.getRecord(key);
    if (existing === null) {
      await this.set(key, value);
    }
  }

  /** 只有规范 ISO 时间才算有效迁移标记。 */
  async hasCompletedMarker(key: string): Promise<boolean> {
    const value = await this.get(key);
    return value !== null && StorageTime.isCanonicalIso(value);
  }

  async recordMigrationResult(migrationId: string, entryId: string, status: string,
    sourceStore: string, sourceKey: string, recordedAt: string): Promise<void> {
    await this.db.execute(RECORD_RESULT_SQL, [
      migrationId, entryId, status, sourceStore, sourceKey, DATABASE_VERSION, recordedAt
    ]);
  }

  async readMigrationResults(migrationId: string): Promise<LegacyMigrationResultRecord[]> {
    const rows: SqlRow[] = await this.db.query(SELECT_RESULTS_SQL, [migrationId]);
    return rows.map((row: SqlRow): LegacyMigrationResultRecord => {
      return {
        entryId: requiredString(row, LegacyMigrationResultColumns.ENTRY_ID),
        status: requiredString(row, LegacyMigrationResultColumns.STATUS),
        sourceStore: requiredString(row, LegacyMigrationResultColumns.SOURCE_STORE),
        sourceKey: requiredString(row, LegacyMigrationResultColumns.SOURCE_KEY),
        schemaVersion: requiredNumber(row, LegacyMigrationResultColumns.SCHEMA_VERSION),
        recordedAt: requiredString(row, LegacyMigrationResultColumns.RECORDED_AT)
      };
    });
  }
}
