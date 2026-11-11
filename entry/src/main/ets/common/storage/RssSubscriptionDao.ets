import { DATABASE_VERSION, RssSubscriptionColumns } from './DatabaseSchema';
import {
  SqlDatabase,
  SqlRow,
  UnsupportedStorageVersionError,
  requiredNumber,
  requiredString,
  optionalString
} from './SqlDatabase';
import { StorageClock, StorageTime, SystemStorageClock } from './StorageTime';

const TABLE: string = 'rss_subscription';
const SELECT_COLUMNS: string =
  `${RssSubscriptionColumns.STABLE_ID}, ${RssSubscriptionColumns.SORT_KEY}, ` +
  `${RssSubscriptionColumns.SCHEMA_VERSION}, ${RssSubscriptionColumns.FIRST_STORED_AT}, ` +
  `${RssSubscriptionColumns.LAST_CHANGED_AT}, ${RssSubscriptionColumns.MIGRATED_FROM}`;

const SELECT_ALL_SQL: string =
  `SELECT ${SELECT_COLUMNS} FROM ${TABLE} ` +
  `ORDER BY ${RssSubscriptionColumns.SORT_KEY} ASC, ${RssSubscriptionColumns.STABLE_ID} ASC`;
const SELECT_COUNT_SQL: string = `SELECT COUNT(*) AS row_count FROM ${TABLE}`;
const INSERT_SQL: string =
  `INSERT INTO ${TABLE} (${RssSubscriptionColumns.STABLE_ID}, ${RssSubscriptionColumns.SORT_KEY}, ` +
  `${RssSubscriptionColumns.SCHEMA_VERSION}, ${RssSubscriptionColumns.FIRST_STORED_AT}, ` +
  `${RssSubscriptionColumns.LAST_CHANGED_AT}, ${RssSubscriptionColumns.MIGRATED_FROM}) VALUES (?, ?, ?, ?, ?, ?)`;
const UPDATE_KEY_SQL: string =
  `UPDATE ${TABLE} SET ${RssSubscriptionColumns.SORT_KEY} = ?, ` +
  `${RssSubscriptionColumns.LAST_CHANGED_AT} = ? WHERE ${RssSubscriptionColumns.STABLE_ID} = ?`;
const DELETE_ONE_SQL: string = `DELETE FROM ${TABLE} WHERE ${RssSubscriptionColumns.STABLE_ID} = ?`;
const CLEAR_SQL: string = `DELETE FROM ${TABLE}`;

export interface RssSubscriptionRecord {
  stableId: string;
  sortKey: number;
  schemaVersion: number;
  firstStoredAt: string;
  lastChangedAt: string;
  migratedFrom: string | null;
}

/**
 * rss_subscription 的低层读写；事务由 RssSubscriptionRepository 控制。
 *
 * 顺序模型见 DatabaseSchema：`sort_key` 升序即展示顺序，且有 UNIQUE 约束。
 * 纯删除、纯首尾插入都不动已有行的 key/时间戳；只有相对顺序变化才整表重新编号。
 */
export class RssSubscriptionDao {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getAll(): Promise<string[]> {
    const rows: SqlRow[] = await this.db.query(SELECT_ALL_SQL);
    const stableIds: string[] = [];
    for (const row of rows) {
      const record = RssSubscriptionDao.toRecord(row);
      RssSubscriptionDao.assertReadable(record);
      stableIds.push(record.stableId);
    }
    return stableIds;
  }

  async count(): Promise<number> {
    const rows: SqlRow[] = await this.db.query(SELECT_COUNT_SQL);
    if (rows.length === 0) {
      return 0;
    }
    return requiredNumber(rows[0], 'row_count');
  }

  /**
   * 用完整顺序覆盖订阅列表：
   * - 不在列表里的 id → 逐条 DELETE（不拼 `IN (?, …)` 动态参数，列表再长也不会撞变量上限）；
   * - 新 id 只出现在头/尾且已有项相对顺序不变 → 只插新行（O(新增数)）；
   * - 相对顺序真的变化（或中间插入）→ 整表重新编号，新编号从 MAX+1 起，不会撞 UNIQUE；
   * - 已有项的 first_stored_at 永远保留，last_changed_at 只在 key 真的变化时更新；
   * - 入参重复 id 按首次出现去重（重复订阅没有意义）。
   */
  async replaceOrder(stableIds: string[]): Promise<void> {
    const requested: string[] = RssSubscriptionDao.dedupe(stableIds);
    const rows: SqlRow[] = await this.db.query(SELECT_ALL_SQL);
    const existing: Map<string, RssSubscriptionRecord> = new Map<string, RssSubscriptionRecord>();
    for (const row of rows) {
      const record = RssSubscriptionDao.toRecord(row);
      RssSubscriptionDao.assertWritable(record);
      existing.set(record.stableId, record);
    }

    const requestedSet: Set<string> = new Set<string>(requested);
    for (const record of existing.values()) {
      if (!requestedSet.has(record.stableId)) {
        await this.db.execute(DELETE_ONE_SQL, [record.stableId]);
      }
    }

    const survivorsOld: string[] = [];
    for (const row of rows) {
      const stableId = requiredString(row, RssSubscriptionColumns.STABLE_ID);
      if (requestedSet.has(stableId)) {
        survivorsOld.push(stableId);
      }
    }
    const survivorsNew: string[] = [];
    for (const stableId of requested) {
      if (existing.has(stableId)) {
        survivorsNew.push(stableId);
      }
    }

    const now = this.clock.nowIso();
    if (RssSubscriptionDao.sameOrder(survivorsOld, survivorsNew)
      && RssSubscriptionDao.insertsOnlyAtEdges(requested, existing)) {
      await this.insertAtEdges(existing, requested, now);
      return;
    }
    await this.renumberAll(existing, requested, now);
  }

  /** 迁移专用：目标表非空时返回 false（不合并、不覆盖）。 */
  async insertMigrated(stableIds: string[], now: string, source: string): Promise<boolean> {
    if ((await this.count()) > 0) {
      return false;
    }
    for (let index = 0; index < stableIds.length; index++) {
      await this.db.execute(INSERT_SQL, [
        stableIds[index], index, DATABASE_VERSION, now, now, source + '#index=' + index
      ]);
    }
    return true;
  }

  /** 只在两端插入时，已有行完全不动：头部按 MIN-1 递减，尾部按 MAX+1 递增。 */
  private async insertAtEdges(existing: Map<string, RssSubscriptionRecord>, requested: string[],
    now: string): Promise<void> {
    let minKey: number | null = null;
    let maxKey: number | null = null;
    for (const stableId of requested) {
      const record = existing.get(stableId);
      if (record === undefined) {
        continue;
      }
      if (minKey === null || record.sortKey < minKey) {
        minKey = record.sortKey;
      }
      if (maxKey === null || record.sortKey > maxKey) {
        maxKey = record.sortKey;
      }
    }

    const leading: string[] = [];
    let index = 0;
    while (index < requested.length && !existing.has(requested[index])) {
      leading.push(requested[index]);
      index++;
    }
    const trailing: string[] = [];
    index = requested.length - 1;
    while (index >= 0 && !existing.has(requested[index])) {
      trailing.push(requested[index]);
      index--;
    }

    if (minKey === null || maxKey === null) {
      // 空表：0..n-1
      for (let position = 0; position < requested.length; position++) {
        await this.insertRow(requested[position], position, now);
      }
      return;
    }
    for (let position = 0; position < leading.length; position++) {
      await this.insertRow(leading[position], minKey - leading.length + position, now);
    }
    let nextKey: number = maxKey + 1;
    for (let position = trailing.length - 1; position >= 0; position--) {
      await this.insertRow(trailing[position], nextKey, now);
      nextKey++;
    }
  }

  /** 整表重新编号：新 key 全部大于现有 MAX，逐条写不会触发 UNIQUE 冲突。 */
  private async renumberAll(existing: Map<string, RssSubscriptionRecord>, requested: string[],
    now: string): Promise<void> {
    let maxKey: number | null = null;
    for (const record of existing.values()) {
      if (maxKey === null || record.sortKey > maxKey) {
        maxKey = record.sortKey;
      }
    }
    let nextKey: number = maxKey === null ? 0 : maxKey + 1;
    for (const stableId of requested) {
      const record = existing.get(stableId);
      if (record === undefined) {
        await this.insertRow(stableId, nextKey, now);
      } else {
        const lastChangedAt = StorageTime.clampChangedAt(record.firstStoredAt, now);
        await this.db.execute(UPDATE_KEY_SQL, [nextKey, lastChangedAt, stableId]);
      }
      nextKey++;
    }
  }

  private async insertRow(stableId: string, sortKey: number, now: string): Promise<void> {
    await this.db.execute(INSERT_SQL, [stableId, sortKey, DATABASE_VERSION, now, now, null]);
  }

  private static dedupe(stableIds: string[]): string[] {
    const seen: Set<string> = new Set<string>();
    const unique: string[] = [];
    for (const stableId of stableIds) {
      if (stableId.length === 0 || seen.has(stableId)) {
        continue;
      }
      seen.add(stableId);
      unique.push(stableId);
    }
    return unique;
  }

  private static sameOrder(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index++) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  /** 新 id 是否只出现在已有项的头/尾连成块（中间插入必须整表重编号）。 */
  private static insertsOnlyAtEdges(requested: string[],
    existing: Map<string, RssSubscriptionRecord>): boolean {
    let firstSurvivor = 0;
    while (firstSurvivor < requested.length && !existing.has(requested[firstSurvivor])) {
      firstSurvivor++;
    }
    if (firstSurvivor === requested.length) {
      return true;
    }
    let lastSurvivor = requested.length - 1;
    while (lastSurvivor >= 0 && !existing.has(requested[lastSurvivor])) {
      lastSurvivor--;
    }
    for (let index = firstSurvivor; index <= lastSurvivor; index++) {
      if (!existing.has(requested[index])) {
        return false;
      }
    }
    return true;
  }

  private static assertWritable(record: RssSubscriptionRecord): void {
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'rss_subscription schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
  }

  private static assertReadable(record: RssSubscriptionRecord): void {
    if (record.schemaVersion !== DATABASE_VERSION) {
      throw new UnsupportedStorageVersionError(
        'rss_subscription schema_version=' + record.schemaVersion + ' but app expects ' + DATABASE_VERSION);
    }
  }

  private static toRecord(row: SqlRow): RssSubscriptionRecord {
    return {
      stableId: requiredString(row, RssSubscriptionColumns.STABLE_ID),
      sortKey: requiredNumber(row, RssSubscriptionColumns.SORT_KEY),
      schemaVersion: requiredNumber(row, RssSubscriptionColumns.SCHEMA_VERSION),
      firstStoredAt: requiredString(row, RssSubscriptionColumns.FIRST_STORED_AT),
      lastChangedAt: requiredString(row, RssSubscriptionColumns.LAST_CHANGED_AT),
      migratedFrom: optionalString(row, RssSubscriptionColumns.MIGRATED_FROM)
    };
  }
}
