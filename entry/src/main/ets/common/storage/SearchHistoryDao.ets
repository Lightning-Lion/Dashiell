import { DATABASE_VERSION, SearchHistoryColumns } from './DatabaseSchema';
import {
  SqlDatabase,
  SqlRow,
  UnsupportedStorageVersionError,
  requiredNumber,
  requiredString,
  optionalString
} from './SqlDatabase';
import { StorageClock, StorageTime, SystemStorageClock } from './StorageTime';

const TABLE: string = 'search_history';
const SELECT_COLUMNS: string =
  `${SearchHistoryColumns.KEYWORD}, ${SearchHistoryColumns.SORT_KEY}, ` +
  `${SearchHistoryColumns.SCHEMA_VERSION}, ${SearchHistoryColumns.FIRST_STORED_AT}, ` +
  `${SearchHistoryColumns.LAST_CHANGED_AT}, ${SearchHistoryColumns.MIGRATED_FROM}`;

const SELECT_ALL_SQL: string =
  `SELECT ${SELECT_COLUMNS} FROM ${TABLE} ` +
  `ORDER BY ${SearchHistoryColumns.SORT_KEY} ASC, ${SearchHistoryColumns.KEYWORD} ASC`;
const SELECT_ONE_SQL: string =
  `SELECT ${SELECT_COLUMNS} FROM ${TABLE} WHERE ${SearchHistoryColumns.KEYWORD} = ?`;
const SELECT_COUNT_SQL: string = `SELECT COUNT(*) AS row_count FROM ${TABLE}`;
const SELECT_MIN_KEY_SQL: string = `SELECT MIN(${SearchHistoryColumns.SORT_KEY}) AS min_key FROM ${TABLE}`;

const INSERT_SQL: string =
  `INSERT INTO ${TABLE} (${SearchHistoryColumns.KEYWORD}, ${SearchHistoryColumns.SORT_KEY}, ` +
  `${SearchHistoryColumns.SCHEMA_VERSION}, ${SearchHistoryColumns.FIRST_STORED_AT}, ` +
  `${SearchHistoryColumns.LAST_CHANGED_AT}, ${SearchHistoryColumns.MIGRATED_FROM}) VALUES (?, ?, ?, ?, ?, ?)`;

const MOVE_TO_TOP_SQL: string =
  `UPDATE ${TABLE} SET ${SearchHistoryColumns.SORT_KEY} = ?, ${SearchHistoryColumns.LAST_CHANGED_AT} = ? ` +
  `WHERE ${SearchHistoryColumns.KEYWORD} = ?`;

// 保留 sort_key 最小的 maxCount 条；按 (sort_key, keyword) 排序保证裁剪边界确定。
const TRIM_SQL: string =
  `DELETE FROM ${TABLE} WHERE ${SearchHistoryColumns.KEYWORD} NOT IN (` +
  `SELECT ${SearchHistoryColumns.KEYWORD} FROM ${TABLE} ` +
  `ORDER BY ${SearchHistoryColumns.SORT_KEY} ASC, ${SearchHistoryColumns.KEYWORD} ASC LIMIT ?)`;
const DELETE_SQL: string = `DELETE FROM ${TABLE} WHERE ${SearchHistoryColumns.KEYWORD} = ?`;
const CLEAR_SQL: string = `DELETE FROM ${TABLE}`;

export interface SearchHistoryRecord {
  keyword: string;
  sortKey: number;
  schemaVersion: number;
  firstStoredAt: string;
  lastChangedAt: string;
  migratedFrom: string | null;
}

/**
 * search_history 的低层读写；事务由 SearchHistoryRepository 控制。
 *
 * 顺序模型见 DatabaseSchema：`sort_key` 升序即展示顺序（最前 = 最近一次搜索），
 * 且有 UNIQUE 约束。新增/置顶都是"取 MIN-1 写一行"，不再做全表 +1 位移。
 */
export class SearchHistoryDao {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getAll(): Promise<string[]> {
    const rows: SqlRow[] = await this.db.query(SELECT_ALL_SQL);
    const keywords: string[] = [];
    for (const row of rows) {
      const record = SearchHistoryDao.toRecord(row);
      SearchHistoryDao.assertReadable(record);
      keywords.push(record.keyword);
    }
    return keywords;
  }

  async getRecord(keyword: string): Promise<SearchHistoryRecord | null> {
    const rows: SqlRow[] = await this.db.query(SELECT_ONE_SQL, [keyword]);
    if (rows.length === 0) {
      return null;
    }
    return SearchHistoryDao.toRecord(rows[0]);
  }

  async count(): Promise<number> {
    const rows: SqlRow[] = await this.db.query(SELECT_COUNT_SQL);
    if (rows.length === 0) {
      return 0;
    }
    return requiredNumber(rows[0], 'row_count');
  }

  /** 新增一条到最前：sort_key = MIN-1（空表用 0）。只写一行。 */
  async insertNew(keyword: string, now: string): Promise<void> {
    const frontKey = await this.frontKey();
    await this.db.execute(INSERT_SQL, [keyword, frontKey, DATABASE_VERSION, now, now, null]);
  }

  /** 已存在关键字真正换位时才更新时间；原本就在最前返回 false。只写一行。 */
  async moveExistingToTop(record: SearchHistoryRecord, now: string): Promise<boolean> {
    SearchHistoryDao.assertWritable(record);
    const minKey = await this.minKey();
    if (minKey !== null && record.sortKey === minKey) {
      return false;
    }
    const lastChangedAt = StorageTime.clampChangedAt(record.firstStoredAt, now);
    await this.db.execute(MOVE_TO_TOP_SQL, [minKey === null ? 0 : minKey - 1, lastChangedAt, record.keyword]);
    return true;
  }

  /** 只保留最近的 maxCount 条（sort_key 最小的那些）。 */
  async trimToMax(maxCount: number): Promise<void> {
    if (maxCount <= 0) {
      await this.db.execute(CLEAR_SQL);
      return;
    }
    await this.db.execute(TRIM_SQL, [maxCount]);
  }

  async remove(keyword: string): Promise<void> {
    await this.db.execute(DELETE_SQL, [keyword]);
  }

  async clear(): Promise<void> {
    await this.db.execute(CLEAR_SQL);
  }

  /** 迁移专用：目标表非空时返回 false（不合并、不覆盖）。 */
  async insertMigrated(keywords: string[], now: string, source: string): Promise<boolean> {
    if ((await this.count()) > 0) {
      return false;
    }
    for (let index = 0; index < keywords.length; index++) {
      await this.db.execute(INSERT_SQL, [
        keywords[index], index, DATABASE_VERSION, now, now, source + '#index=' + index
      ]);
    }
    return true;
  }

  private async minKey(): Promise<number | null> {
    const rows: SqlRow[] = await this.db.query(SELECT_MIN_KEY_SQL);
    if (rows.length === 0) {
      return null;
    }
    const value = rows[0].get('min_key');
    return typeof value === 'number' ? value : null;
  }

  private async frontKey(): Promise<number> {
    const minKey = await this.minKey();
    return minKey === null ? 0 : minKey - 1;
  }

  private static assertWritable(record: SearchHistoryRecord): void {
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'search_history schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
  }

  private static assertReadable(record: SearchHistoryRecord): void {
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'search_history schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
  }

  private static toRecord(row: SqlRow): SearchHistoryRecord {
    return {
      keyword: requiredString(row, SearchHistoryColumns.KEYWORD),
      sortKey: requiredNumber(row, SearchHistoryColumns.SORT_KEY),
      schemaVersion: requiredNumber(row, SearchHistoryColumns.SCHEMA_VERSION),
      firstStoredAt: requiredString(row, SearchHistoryColumns.FIRST_STORED_AT),
      lastChangedAt: requiredString(row, SearchHistoryColumns.LAST_CHANGED_AT),
      migratedFrom: optionalString(row, SearchHistoryColumns.MIGRATED_FROM)
    };
  }
}
