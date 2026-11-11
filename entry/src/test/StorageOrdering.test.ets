import { describe, it, expect, beforeAll, beforeEach, afterAll } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { CREATE_SCHEMA_SQL } from '../main/ets/common/storage/DatabaseSchema';
import { RdbSqlDatabase } from '../main/ets/common/storage/RdbSqlDatabase';
import { RssSubscriptionRepository } from '../main/ets/common/storage/RssSubscriptionRepository';
import { SearchHistoryDao } from '../main/ets/common/storage/SearchHistoryDao';
import { SearchHistoryRepository } from '../main/ets/common/storage/SearchHistoryRepository';
import { StorageClock } from '../main/ets/common/storage/StorageTime';

const DB_NAME: string = 'storage_ordering_test.db';

class FixedClock implements StorageClock {
  private value: string = '2026-10-22T06:00:00.000Z';

  nowIso(): string {
    return this.value;
  }

  advanceSeconds(seconds: number): string {
    this.value = new Date(Date.parse(this.value) + seconds * 1000).toISOString();
    return this.value;
  }
}

/** 真机上的顺序回归：生产 DDL + 生产 Repository，验证 sort_key(UNIQUE) 模型的可见行为。 */
class ProbeDatabase {
  private readonly appContext: common.Context;
  private rdbContext: common.Context | null = null;
  private store: relationalStore.RdbStore | null = null;
  db: RdbSqlDatabase | null = null;

  constructor() {
    this.appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  }

  async open(): Promise<RdbSqlDatabase> {
    const topAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
    this.rdbContext = topAbility === undefined ? this.appContext : topAbility.context;
    this.store = await relationalStore.getRdbStore(this.rdbContext, {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    });
    this.db = new RdbSqlDatabase(this.store);
    for (const statement of CREATE_SCHEMA_SQL) {
      await this.db.execute(statement);
    }
    return this.db;
  }

  async clearAll(): Promise<void> {
    const db = this.requireDb();
    await db.execute('DELETE FROM search_history');
    await db.execute('DELETE FROM rss_subscription');
  }

  requireDb(): RdbSqlDatabase {
    if (this.db === null) {
      throw new Error('probe db is not open');
    }
    return this.db;
  }

  async close(): Promise<void> {
    if (this.store !== null) {
      await this.store.close();
      this.store = null;
    }
    this.db = null;
    if (this.rdbContext !== null) {
      try {
        await relationalStore.deleteRdbStore(this.rdbContext, DB_NAME);
      } catch (error) {
        // 清库失败不影响用例结论。
      }
    }
  }
}

async function sortKeys(db: RdbSqlDatabase, table: string): Promise<string[]> {
  const rows = await db.query(`SELECT sort_key FROM ${table} ORDER BY sort_key`);
  const keys: string[] = [];
  for (const row of rows) {
    keys.push(String(row.get('sort_key')));
  }
  return keys;
}

export default function storageOrderingTest() {
  describe('storageOrdering', () => {
    let probe = new ProbeDatabase();
    let clock = new FixedClock();

    beforeAll(async () => {
      probe = new ProbeDatabase();
      await probe.open();
    });

    beforeEach(async () => {
      clock = new FixedClock();
      await probe.clearAll();
    });

    afterAll(async () => {
      await probe.close();
    });

    it('searchHistoryPrependsWithoutShifting', 0, async () => {
      const db = probe.requireDb();
      const repo = new SearchHistoryRepository(db, clock);
      const dao = new SearchHistoryDao(db, clock);

      await repo.add('alpha');
      clock.advanceSeconds(10);
      await repo.add('beta');
      clock.advanceSeconds(10);
      await repo.add('gamma');
      expect(await repo.getAll()).assertDeepEquals(['gamma', 'beta', 'alpha']);
      // 头插只递减新行：-2 / -1 / 0，没有全表位移。
      expect(await sortKeys(db, 'search_history')).assertDeepEquals(['-2', '-1', '0']);

      const alphaBefore = await dao.getRecord('alpha');
      const t0 = alphaBefore === null ? '' : alphaBefore.firstStoredAt;
      clock.advanceSeconds(10);
      await repo.add('alpha');
      expect(await repo.getAll()).assertDeepEquals(['alpha', 'gamma', 'beta']);
      const alphaAfter = await dao.getRecord('alpha');
      expect(alphaAfter === null ? '' : alphaAfter.firstStoredAt).assertEqual(t0);
      expect(alphaAfter === null ? '' : alphaAfter.lastChangedAt).assertEqual(clock.nowIso());
      expect(alphaAfter === null ? 0 : alphaAfter.sortKey).assertEqual(-3);
    });

    it('searchHistoryTrimKeepsNewest', 0, async () => {
      const repo = new SearchHistoryRepository(probe.requireDb(), clock);
      for (const keyword of ['one', 'two', 'three', 'four', 'five']) {
        clock.advanceSeconds(10);
        await repo.add(keyword);
      }
      expect(await repo.getAll()).assertDeepEquals(['five', 'four', 'three', 'two', 'one']);
      await new SearchHistoryDao(probe.requireDb(), clock).trimToMax(2);
      expect(await repo.getAll()).assertDeepEquals(['five', 'four']);
    });

    it('rssOrderFollowsInputAndStaysUnique', 0, async () => {
      const db = probe.requireDb();
      const repo = new RssSubscriptionRepository(db, clock);

      await repo.replaceOrder(['a', 'b', 'c']);
      expect(await repo.getAll()).assertDeepEquals(['a', 'b', 'c']);
      expect(await sortKeys(db, 'rss_subscription')).assertDeepEquals(['0', '1', '2']);

      await repo.replaceOrder(['c', 'a', 'b']);
      expect(await repo.getAll()).assertDeepEquals(['c', 'a', 'b']);

      // 头部/尾部插入不动已有行。
      await repo.replaceOrder(['x', 'c', 'a', 'b', 'y']);
      expect(await repo.getAll()).assertDeepEquals(['x', 'c', 'a', 'b', 'y']);

      // 中间插入必须重编号，顺序仍然正确。
      await repo.replaceOrder(['x', 'm', 'c', 'a', 'b', 'y']);
      expect(await repo.getAll()).assertDeepEquals(['x', 'm', 'c', 'a', 'b', 'y']);

      // 重复 id 去重，不炸主键。
      await repo.replaceOrder(['x', 'x', 'c']);
      expect(await repo.getAll()).assertDeepEquals(['x', 'c']);

      const keys = await sortKeys(db, 'rss_subscription');
      expect(keys.length).assertEqual(2);
      expect(keys[0] === keys[1]).assertFalse();

      await repo.replaceOrder([]);
      expect((await repo.getAll()).length).assertEqual(0);
    });

    it('sortKeyRejectsDuplicates', 0, async () => {
      const db = probe.requireDb();
      await db.execute(
        `INSERT INTO rss_subscription (stable_id, sort_key, schema_version, first_stored_at, last_changed_at)
         VALUES (?, ?, 2, ?, ?)`, ['a', 7, '2026-10-22T06:00:00.000Z', '2026-10-22T06:00:00.000Z']);
      let rejected = false;
      try {
        await db.execute(
          `INSERT INTO rss_subscription (stable_id, sort_key, schema_version, first_stored_at, last_changed_at)
           VALUES (?, ?, 2, ?, ?)`, ['b', 7, '2026-10-22T06:00:00.000Z', '2026-10-22T06:00:00.000Z']);
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
