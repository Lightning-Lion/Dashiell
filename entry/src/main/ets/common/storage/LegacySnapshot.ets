/**
 * 旧存储的只读快照接口。
 * 迁移逻辑只依赖这个接口，主机测试可以注入内存实现。
 */
export enum LegacyReadStatus {
  MISSING = 0,
  VALUE = 1,
  INVALID = 2,
  ERROR = 3
}

export interface LegacyBooleanResult {
  status: LegacyReadStatus;
  value: boolean | null;
}

export interface LegacyStringListResult {
  status: LegacyReadStatus;
  values: string[] | null;
}

export interface LegacyPersonalizedResult {
  status: LegacyReadStatus;
  enabled: boolean | null;
  lastChangedAt: string | null;
}

export interface LegacyTimestampResult {
  status: LegacyReadStatus;
  timestamp: string | null;
}

export interface LegacySnapshotReader {
  readPrivacyConsent(): Promise<LegacyBooleanResult>;

  readLoggedInAtLeastOnce(): Promise<LegacyBooleanResult>;

  readSearchHistory(): Promise<LegacyStringListResult>;

  readRssSources(): Promise<LegacyStringListResult>;

  readPersonalized(): Promise<LegacyPersonalizedResult>;

  readDouyinCacheTimestamp(): Promise<LegacyTimestampResult>;
}
