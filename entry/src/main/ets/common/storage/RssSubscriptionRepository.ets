import { RssSubscriptionDao } from './RssSubscriptionDao';
import { SqlDatabase } from './SqlDatabase';
import { StorageClock, SystemStorageClock } from './StorageTime';

/** RSS 订阅事务入口；以完整顺序覆盖，保留已存在项的首次存储时间。 */
export class RssSubscriptionRepository {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getAll(): Promise<string[]> {
    return new RssSubscriptionDao(this.db, this.clock).getAll();
  }

  async count(): Promise<number> {
    return new RssSubscriptionDao(this.db, this.clock).count();
  }

  async replaceOrder(stableIds: string[]): Promise<void> {
    await this.db.transaction(async (tx: SqlDatabase): Promise<void> => {
      await new RssSubscriptionDao(tx, this.clock).replaceOrder(stableIds);
    });
  }
}
