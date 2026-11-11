import { describe, it, expect, beforeAll, beforeEach, afterAll } from '@ohos/hypium';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { RdbSqlDatabase } from '../main/ets/common/storage/RdbSqlDatabase';

const DB_NAME: string = 'storage_bind_args_test.db';
const TABLE: string = 'bind_args_probe';

/**
 * 回归用例：ArkUI V2 的 @Trace 数组是代理对象，直接当 bindArgs 交给 relationalStore
 * 会被拒/丢元素（设备日志：bind args count(0) > numParameters(1)；JS 层：The values must be a
 * BindArgs array），导致 rss_subscription 的 `DELETE ... NOT IN (?)` 整条事务回滚。
 * 这里跑真实 RDB，并且必须经由 RdbSqlDatabase 才能覆盖到绑定层的归一化。
 */
@ObservedV2
class TrackedStableIds {
  @Trace ids: string[] = [];
}

class ProbeStore {
  private readonly appContext: common.Context;
  private rdbContext: common.Context | null = null;
  private store: relationalStore.RdbStore | null = null;

  constructor() {
    this.appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  }

  /** RDB 要求能力上下文；测试进程里 getAppContext() 会被 401 Illegal context 拒绝。 */
  async open(): Promise<RdbSqlDatabase> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const topAbility = await delegator.getCurrentTopAbility();
    this.rdbContext = topAbility === undefined ? this.appContext : topAbility.context;
    this.store = await relationalStore.getRdbStore(this.rdbContext, {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    });
    const db = new RdbSqlDatabase(this.store);
    await db.execute(`CREATE TABLE IF NOT EXISTS ${TABLE} (station_id TEXT NOT NULL)`);
    return db;
  }

  async close(): Promise<void> {
    if (this.store !== null) {
      await this.store.close();
      this.store = null;
    }
    if (this.rdbContext !== null) {
      try {
        await relationalStore.deleteRdbStore(this.rdbContext, DB_NAME);
      } catch (error) {
        // 清库失败不影响用例结论。
      }
    }
  }
}

async function seed(db: RdbSqlDatabase): Promise<void> {
  await db.execute(`DELETE FROM ${TABLE}`);
  await db.execute(`INSERT INTO ${TABLE} (station_id) VALUES (?)`, ['bilibili']);
  await db.execute(`INSERT INTO ${TABLE} (station_id) VALUES (?)`, ['zhihu']);
}

async function remaining(db: RdbSqlDatabase): Promise<string[]> {
  const rows = await db.query(`SELECT station_id FROM ${TABLE}`);
  const stableIds: string[] = [];
  for (const row of rows) {
    stableIds.push(String(row.get('station_id')));
  }
  stableIds.sort();
  return stableIds;
}

export default function storageBindArgsTest() {
  describe('storageBindArgs', () => {
    let probe = new ProbeStore();
    let db: RdbSqlDatabase | null = null;

    beforeAll(async () => {
      probe = new ProbeStore();
      db = await probe.open();
    });

    beforeEach(async () => {
      if (db === null) {
        throw new Error('probe db is not open');
      }
      await seed(db);
    });

    afterAll(async () => {
      await probe.close();
    });

    it('bindsPlainStringArray', 0, async () => {
      const plain: string[] = ['bilibili'];
      await db?.execute(`DELETE FROM ${TABLE} WHERE station_id NOT IN (?)`, plain);
      expect(await remaining(db as RdbSqlDatabase)).assertDeepEquals(['bilibili']);
    });

    it('bindsTraceProxyArrayFromObservedV2', 0, async () => {
      const tracked = new TrackedStableIds();
      tracked.ids.push('zhihu');
      expect(tracked.ids.length).assertEqual(1);
      // 修复前：The values must be a BindArgs array（真机上表现为 bind args count(0)）。
      await db?.execute(`DELETE FROM ${TABLE} WHERE station_id NOT IN (?)`, tracked.ids);
      expect(await remaining(db as RdbSqlDatabase)).assertDeepEquals(['zhihu']);
    });


    it('bindsSliceOfTraceArray', 0, async () => {
      const tracked = new TrackedStableIds();
      tracked.ids.push('zhihu');
      const sliced: string[] = tracked.ids.slice();
      await db?.execute(`DELETE FROM ${TABLE} WHERE station_id NOT IN (?)`, sliced);
      expect(await remaining(db as RdbSqlDatabase)).assertDeepEquals(['zhihu']);
    });

    it('bindsCopiedTraceArray', 0, async () => {
      const tracked = new TrackedStableIds();
      tracked.ids.push('zhihu');
      const copy: string[] = [];
      for (let index = 0; index < tracked.ids.length; index++) {
        copy.push(tracked.ids[index]);
      }
      await db?.execute(`DELETE FROM ${TABLE} WHERE station_id NOT IN (?)`, copy);
      expect(await remaining(db as RdbSqlDatabase)).assertDeepEquals(['zhihu']);
    });
  });
}
