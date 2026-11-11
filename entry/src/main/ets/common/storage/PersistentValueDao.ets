import { DATABASE_VERSION, PersistentValueColumns } from './DatabaseSchema';
import {
  SqlDatabase,
  SqlRow,
  UnsupportedStorageVersionError,
  requiredNumber,
  requiredString,
  optionalNumber,
  optionalString
} from './SqlDatabase';
import { StorageClock, StorageTime, SystemStorageClock } from './StorageTime';

const TABLE: string = 'persistent_value';
const SELECT_COLUMNS: string =
  `${PersistentValueColumns.KEY}, ${PersistentValueColumns.NAMESPACE}, ` +
  `${PersistentValueColumns.TYPE}, ${PersistentValueColumns.TEXT}, ` +
  `${PersistentValueColumns.INTEGER}, ${PersistentValueColumns.REAL}, ` +
  `${PersistentValueColumns.SCHEMA_VERSION}, ${PersistentValueColumns.FIRST_STORED_AT}, ` +
  `${PersistentValueColumns.LAST_CHANGED_AT}, ${PersistentValueColumns.MIGRATED_FROM}`;

const SELECT_SQL: string = `SELECT ${SELECT_COLUMNS} FROM ${TABLE} WHERE ${PersistentValueColumns.KEY} = ?`;

const INSERT_SQL: string =
  `INSERT INTO ${TABLE} (${PersistentValueColumns.KEY}, ${PersistentValueColumns.NAMESPACE}, ` +
  `${PersistentValueColumns.TYPE}, ${PersistentValueColumns.TEXT}, ${PersistentValueColumns.INTEGER}, ` +
  `${PersistentValueColumns.REAL}, ${PersistentValueColumns.SCHEMA_VERSION}, ` +
  `${PersistentValueColumns.FIRST_STORED_AT}, ${PersistentValueColumns.LAST_CHANGED_AT}, ` +
  `${PersistentValueColumns.MIGRATED_FROM}) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

const UPDATE_SQL: string =
  `UPDATE ${TABLE} SET ${PersistentValueColumns.NAMESPACE} = ?, ${PersistentValueColumns.TYPE} = ?, ` +
  `${PersistentValueColumns.TEXT} = ?, ${PersistentValueColumns.INTEGER} = ?, ` +
  `${PersistentValueColumns.REAL} = ?, ${PersistentValueColumns.SCHEMA_VERSION} = ?, ` +
  `${PersistentValueColumns.LAST_CHANGED_AT} = ? WHERE ${PersistentValueColumns.KEY} = ?`;

const DELETE_SQL: string = `DELETE FROM ${TABLE} WHERE ${PersistentValueColumns.KEY} = ?`;

export interface PersistentValueRecord {
  key: string;
  namespace: string;
  type: string;
  textValue: string | null;
  integerValue: number | null;
  realValue: number | null;
  schemaVersion: number;
  firstStoredAt: string;
  lastChangedAt: string;
  migratedFrom: string | null;
}

/**
 * persistent_value 的低层读写。事务由 Repository / Migration 负责。
 * 相同值重复写入不改变 last_changed_at；first_stored_at 永不更新。
 */
export class PersistentValueDao {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getRecord(key: string): Promise<PersistentValueRecord | null> {
    const rows: SqlRow[] = await this.db.query(SELECT_SQL, [key]);
    if (rows.length === 0) {
      return null;
    }
    return PersistentValueDao.toRecord(rows[0]);
  }

  async setBoolean(key: string, namespace: string, value: boolean): Promise<boolean> {
    return this.writeTyped(key, namespace, 'boolean', null, value ? 1 : 0, null);
  }

  async setString(key: string, namespace: string, value: string): Promise<boolean> {
    return this.writeTyped(key, namespace, 'string', value, null, null);
  }

  /** 迁移专用：只在目标不存在时写入，并保留旧时间戳。 */
  async insertMigratedBoolean(key: string, namespace: string, value: boolean,
    firstStoredAt: string, lastChangedAt: string, migratedFrom: string): Promise<boolean> {
    return this.insertMigrated(key, namespace, 'boolean', null, value ? 1 : 0, null,
      firstStoredAt, lastChangedAt, migratedFrom);
  }

  /** 迁移专用：只在目标不存在时写入，并保留旧时间戳。 */
  async insertMigratedString(key: string, namespace: string, value: string,
    firstStoredAt: string, lastChangedAt: string, migratedFrom: string): Promise<boolean> {
    return this.insertMigrated(key, namespace, 'string', value, null, null,
      firstStoredAt, lastChangedAt, migratedFrom);
  }

  async remove(key: string): Promise<void> {
    await this.db.execute(DELETE_SQL, [key]);
  }

  private async writeTyped(key: string, namespace: string, type: string,
    textValue: string | null, integerValue: number | null, realValue: number | null): Promise<boolean> {
    const existing = await this.getRecord(key);
    const now = this.clock.nowIso();
    if (existing === null) {
      await this.db.execute(INSERT_SQL, [
        key, namespace, type, textValue, integerValue, realValue,
        DATABASE_VERSION, now, now, null
      ]);
      return true;
    }
    PersistentValueDao.assertWritable(existing);
    if (existing.type === type && existing.textValue === textValue &&
      existing.integerValue === integerValue && existing.realValue === realValue) {
      return false;
    }
    const lastChangedAt = StorageTime.clampChangedAt(existing.firstStoredAt, now);
    await this.db.execute(UPDATE_SQL, [
      namespace, type, textValue, integerValue, realValue, DATABASE_VERSION, lastChangedAt, key
    ]);
    return true;
  }

  private async insertMigrated(key: string, namespace: string, type: string,
    textValue: string | null, integerValue: number | null, realValue: number | null,
    firstStoredAt: string, lastChangedAt: string, migratedFrom: string): Promise<boolean> {
    const existing = await this.getRecord(key);
    if (existing !== null) {
      return false;
    }
    const now = this.clock.nowIso();
    const first = StorageTime.isCanonicalIso(firstStoredAt) ? firstStoredAt : now;
    const last = StorageTime.clampChangedAt(first, StorageTime.isCanonicalIso(lastChangedAt) ? lastChangedAt : now);
    await this.db.execute(INSERT_SQL, [
      key, namespace, type, textValue, integerValue, realValue,
      DATABASE_VERSION, first, last, migratedFrom
    ]);
    return true;
  }

  private static assertWritable(record: PersistentValueRecord): void {
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'persistent_value schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
  }

  private static toRecord(row: SqlRow): PersistentValueRecord {
    return {
      key: requiredString(row, PersistentValueColumns.KEY),
      namespace: requiredString(row, PersistentValueColumns.NAMESPACE),
      type: requiredString(row, PersistentValueColumns.TYPE),
      textValue: optionalString(row, PersistentValueColumns.TEXT),
      integerValue: optionalNumber(row, PersistentValueColumns.INTEGER),
      realValue: optionalNumber(row, PersistentValueColumns.REAL),
      schemaVersion: requiredNumber(row, PersistentValueColumns.SCHEMA_VERSION),
      firstStoredAt: requiredString(row, PersistentValueColumns.FIRST_STORED_AT),
      lastChangedAt: requiredString(row, PersistentValueColumns.LAST_CHANGED_AT),
      migratedFrom: optionalString(row, PersistentValueColumns.MIGRATED_FROM)
    };
  }
}
