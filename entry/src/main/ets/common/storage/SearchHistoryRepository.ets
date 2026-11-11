import { SearchHistoryDao, SearchHistoryRecord } from './SearchHistoryDao';
import { SqlDatabase } from './SqlDatabase';
import { StorageClock, SystemStorageClock } from './StorageTime';

const MAX_SEARCH_HISTORIES: number = 1000;

/** 搜索历史事务入口；读取保留原错误，让 UI 显示“加载失败”。 */
export class SearchHistoryRepository {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getAll(): Promise<string[]> {
    return new SearchHistoryDao(this.db, this.clock).getAll();
  }

  async count(): Promise<number> {
    return new SearchHistoryDao(this.db, this.clock).count();
  }

  async getRecord(keyword: string): Promise<SearchHistoryRecord | null> {
    return new SearchHistoryDao(this.db, this.clock).getRecord(keyword);
  }

  async add(keyword: string): Promise<void> {
    if (keyword.length === 0) {
      return;
    }
    await this.db.transaction(async (tx: SqlDatabase): Promise<void> => {
      const dao = new SearchHistoryDao(tx, this.clock);
      const existing = await dao.getRecord(keyword);
      const now = this.clock.nowIso();
      if (existing === null) {
        await dao.insertNew(keyword, now);
        // 只有新增会让条数增长；裁剪放在这里，避免每次搜索都扫全表排序。
        if ((await dao.count()) > MAX_SEARCH_HISTORIES) {
          await dao.trimToMax(MAX_SEARCH_HISTORIES);
        }
      } else {
        await dao.moveExistingToTop(existing, now);
      }
    });
  }

  async remove(keyword: string): Promise<void> {
    await this.db.transaction(async (tx: SqlDatabase): Promise<void> => {
      await new SearchHistoryDao(tx, this.clock).remove(keyword);
    });
  }

  async clear(): Promise<void> {
    await this.db.transaction(async (tx: SqlDatabase): Promise<void> => {
      await new SearchHistoryDao(tx, this.clock).clear();
    });
  }
}
