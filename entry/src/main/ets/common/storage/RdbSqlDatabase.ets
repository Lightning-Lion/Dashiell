import { relationalStore } from '@kit.ArkData';
import { SqlDatabase, SqlRow, SqlValue } from './SqlDatabase';

/**
 * 生产环境的 SQL 执行器：把 relationalStore 的 ResultSet 转成列名 → 标量值的 Map。
 * 所有 ResultSet 都在 finally 中 close()。
 */
export class RdbSqlDatabase implements SqlDatabase {
  private readonly store: relationalStore.RdbStore;
  // RDB 同一时刻只允许一个写事务；串行化，避免搜索/聊天式快速操作触发 14800024。
  private writeTail: Promise<void> = Promise.resolve();

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async execute(sql: string, args?: SqlValue[]): Promise<void> {
    await this.store.executeSql(sql, RdbSqlDatabase.toBindArgs(args));
  }

  async query(sql: string, args?: SqlValue[]): Promise<SqlRow[]> {
    const resultSet = await this.store.querySql(sql, RdbSqlDatabase.toBindArgs(args));
    return RdbSqlDatabase.readRows(resultSet);
  }

  async transaction<T>(work: (tx: SqlDatabase) => Promise<T>): Promise<T> {
    const run: Promise<T> = this.writeTail.then((): Promise<T> => this.executeTransaction(work));
    this.writeTail = run.then((): void => {}, (): void => {});
    return run;
  }

  private async executeTransaction<T>(work: (tx: SqlDatabase) => Promise<T>): Promise<T> {
    const transaction = await this.store.createTransaction();
    const transactionDb = new RdbTransactionSqlDatabase(transaction);
    try {
      const result = await work(transactionDb);
      await transaction.commit();
      return result;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_) {
        // 保留原始异常；rollback 失败只影响诊断。
      }
      throw error as Error;
    }
  }

  /**
   * relationalStore 只接受普通数组：ArkUI V2 里 @Trace 装饰的数组是代理对象，
   * 直接透传会在跨界时被拒或丢元素（设备日志：bind args count(0) > numParameters(1)），
   * 所以这里逐元素复制成普通数组再交给 RDB。
   */
  static toBindArgs(args: SqlValue[] | undefined): Array<relationalStore.ValueType> {
    if (args === undefined) {
      return [];
    }
    const bindArgs: Array<relationalStore.ValueType> = [];
    for (let index = 0; index < args.length; index++) {
      bindArgs.push(args[index] as relationalStore.ValueType);
    }
    return bindArgs;
  }

  static readRows(resultSet: relationalStore.ResultSet): SqlRow[] {
    const rows: SqlRow[] = [];
    try {
      const columns: string[] = resultSet.columnNames;
      while (resultSet.goToNextRow()) {
        const row: SqlRow = new Map<string, SqlValue>();
        for (const column of columns) {
          const columnIndex = resultSet.getColumnIndex(column);
          if (columnIndex < 0) {
            continue;
          }
          row.set(column, RdbSqlDatabase.toSqlValue(resultSet.getValue(columnIndex)));
        }
        rows.push(row);
      }
      return rows;
    } finally {
      resultSet.close();
    }
  }

  private static toSqlValue(value: relationalStore.ValueType): SqlValue {
    if (value === null) {
      return null;
    }
    if (typeof value === 'string' || typeof value === 'number') {
      return value;
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0;
    }
    throw new Error('unsupported SQLite value type: ' + typeof value);
  }
}

/** 事务内的执行器；不支持嵌套事务。 */
class RdbTransactionSqlDatabase implements SqlDatabase {
  private readonly tx: relationalStore.Transaction;

  constructor(tx: relationalStore.Transaction) {
    this.tx = tx;
  }

  async execute(sql: string, args?: SqlValue[]): Promise<void> {
    await this.tx.execute(sql, RdbTransactionSqlDatabase.toBindArgs(args));
  }

  async query(sql: string, args?: SqlValue[]): Promise<SqlRow[]> {
    const resultSet = await this.tx.querySql(sql, RdbTransactionSqlDatabase.toBindArgs(args));
    return RdbSqlDatabase.readRows(resultSet);
  }

  transaction<T>(work: (tx: SqlDatabase) => Promise<T>): Promise<T> {
    return Promise.reject(new Error('nested transaction is not supported'));
  }

  private static toBindArgs(args: SqlValue[] | undefined): Array<relationalStore.ValueType> {
    return RdbSqlDatabase.toBindArgs(args);
  }
}
