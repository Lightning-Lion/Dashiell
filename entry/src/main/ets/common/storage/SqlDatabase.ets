/** RDB 中实际使用的标量类型；布尔统一写 1/0。 */
export type SqlValue = string | number | null;

/** 一行查询结果；列名 → 标量值。 */
export type SqlRow = Map<string, SqlValue>;

/**
 * 存储层的最小 SQL 抽象。
 * 生产实现是 RdbSqlDatabase；主机测试用 node:sqlite 实现同一接口。
 */
export interface SqlDatabase {
  execute(sql: string, args?: SqlValue[]): Promise<void>;

  query(sql: string, args?: SqlValue[]): Promise<SqlRow[]>;

  transaction<T>(work: (tx: SqlDatabase) => Promise<T>): Promise<T>;
}

export class StorageFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StorageFormatError';
  }
}

export class UnsupportedStorageVersionError extends StorageFormatError {
  constructor(message: string) {
    super(message);
    this.name = 'UnsupportedStorageVersionError';
  }
}

export class StorageUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StorageUnavailableError';
  }
}

export function requiredString(row: SqlRow, column: string): string {
  const value = row.get(column);
  if (typeof value !== 'string') {
    throw new StorageFormatError('expected string column: ' + column);
  }
  return value;
}

export function requiredNumber(row: SqlRow, column: string): number {
  const value = row.get(column);
  if (typeof value !== 'number') {
    throw new StorageFormatError('expected number column: ' + column);
  }
  return value;
}

export function optionalString(row: SqlRow, column: string): string | null {
  const value = row.get(column);
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw new StorageFormatError('expected nullable string column: ' + column);
  }
  return value;
}

export function optionalNumber(row: SqlRow, column: string): number | null {
  const value = row.get(column);
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'number') {
    throw new StorageFormatError('expected nullable number column: ' + column);
  }
  return value;
}
