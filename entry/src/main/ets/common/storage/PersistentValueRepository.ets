import { logTag } from '../printLog';
import { PersistentValueDao, PersistentValueRecord } from './PersistentValueDao';
import { SqlDatabase } from './SqlDatabase';
import { StorageClock, SystemStorageClock } from './StorageTime';

/**
 * 单值持久化入口：读取失败回退默认值，写入失败抛给调用方处理。
 * 事务在 Repository 层开启，DAO 只做单表操作。
 */
export class PersistentValueRepository {
  private readonly db: SqlDatabase;
  private readonly clock: StorageClock;

  constructor(db: SqlDatabase, clock: StorageClock = new SystemStorageClock()) {
    this.db = db;
    this.clock = clock;
  }

  async getBoolean(key: string, fallback: boolean): Promise<boolean> {
    try {
      const record = await new PersistentValueDao(this.db, this.clock).getRecord(key);
      if (record === null || record.type !== 'boolean' || record.integerValue === null) {
        return fallback;
      }
      return record.integerValue !== 0;
    } catch (error) {
      console.debug(logTag, 'read boolean failed key=' + key + ' error=' + PersistentValueRepository.describe(error));
      return fallback;
    }
  }

  async getString(key: string, fallback: string): Promise<string> {
    try {
      const record = await new PersistentValueDao(this.db, this.clock).getRecord(key);
      if (record === null || record.type !== 'string' || record.textValue === null) {
        return fallback;
      }
      return record.textValue;
    } catch (error) {
      console.debug(logTag, 'read string failed key=' + key + ' error=' + PersistentValueRepository.describe(error));
      return fallback;
    }
  }

  async getRecord(key: string): Promise<PersistentValueRecord | null> {
    return new PersistentValueDao(this.db, this.clock).getRecord(key);
  }

  async setBoolean(key: string, namespace: string, value: boolean): Promise<boolean> {
    return this.db.transaction((tx: SqlDatabase): Promise<boolean> => {
      return new PersistentValueDao(tx, this.clock).setBoolean(key, namespace, value);
    });
  }

  async setString(key: string, namespace: string, value: string): Promise<boolean> {
    return this.db.transaction((tx: SqlDatabase): Promise<boolean> => {
      return new PersistentValueDao(tx, this.clock).setString(key, namespace, value);
    });
  }

  async remove(key: string): Promise<void> {
    await this.db.transaction(async (tx: SqlDatabase): Promise<void> => {
      await new PersistentValueDao(tx, this.clock).remove(key);
    });
  }

  private static describe(error: Object): string {
    const message = (error as Error).message;
    return message === undefined ? 'unknown' : message;
  }
}
