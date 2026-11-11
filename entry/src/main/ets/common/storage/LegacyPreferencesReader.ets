import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PersistenceV2, Type } from '@kit.ArkUI';
import { LocalDataDecoder } from '../local/LocalDataDecoder';
import { JsonDecodeError } from '../jsonschema/JsonDecode';
import { LogEvents } from '../../utils/log/LogEvents.generated';
import { LegacyStorageKeys } from './StorageKeys';
import { StorageTime } from './StorageTime';
import {
  LegacyBooleanResult,
  LegacyPersonalizedResult,
  LegacyReadStatus,
  LegacySnapshotReader,
  LegacyStringListResult,
  LegacyTimestampResult
} from './LegacySnapshot';

interface LegacyRawResult {
  status: LegacyReadStatus;
  value: preferences.ValueType | null;
}

interface LegacyPersonalizedValue {
  enablePersonalized?: boolean;
  updateDate?: Object | null;
}

/**
 * 旧 PersistenceV2 结构；类名和字段名与 cbb63c9 时保持一致，
 * 以便 PersistenceV2 能把旧 key 反序列化回来。
 */
@ObservedV2
class JingxuanRecord {
  @Trace lastCacheDate: Date = new Date();
}

@ObservedV2
class DouYinCacheRecords {
  @Type(JingxuanRecord)
  @Trace jingxuanRecordOrNull: JingxuanRecord | null = null;
}

/**
 * 唯一允许 import preferences / PersistenceV2 的生产文件。
 * 只读旧值，不删除、不写入旧存储。
 */
export class LegacyPreferencesReader implements LegacySnapshotReader {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async readPrivacyConsent(): Promise<LegacyBooleanResult> {
    return this.readBooleanFlag(LegacyStorageKeys.PRIVACY_STORE, LegacyStorageKeys.PRIVACY_KEY);
  }

  async readLoggedInAtLeastOnce(): Promise<LegacyBooleanResult> {
    return this.readBooleanFlag(LegacyStorageKeys.BILI_ACCOUNT_STORE, LegacyStorageKeys.BILI_ACCOUNT_KEY);
  }

  async readSearchHistory(): Promise<LegacyStringListResult> {
    const raw = await this.readRaw(LegacyStorageKeys.SEARCH_HISTORY_STORE, LegacyStorageKeys.SEARCH_HISTORY_KEY);
    if (raw.status !== LegacyReadStatus.VALUE) {
      return { status: raw.status, values: null };
    }
    return LegacyPreferencesReader.toStringList(raw.value);
  }

  async readRssSources(): Promise<LegacyStringListResult> {
    const raw = await this.readRaw(LegacyStorageKeys.RSS_STORE, LegacyStorageKeys.RSS_KEY);
    if (raw.status !== LegacyReadStatus.VALUE) {
      return { status: raw.status, values: null };
    }
    const value = raw.value;
    if (typeof value === 'string') {
      try {
        return { status: LegacyReadStatus.VALUE, values: LocalDataDecoder.parseRSSSourceIds(value) };
      } catch (error) {
        if (error instanceof JsonDecodeError) {
          const issue = error.issues.length > 0 ? error.issues[0] : undefined;
          LogEvents.localDecodeFailed({
            operation: 'rss-source-ids',
            schema: error.schema,
            issueCount: error.issues.length,
            code: issue === undefined ? '' : issue.code,
            path: issue === undefined ? '' : issue.pathText(),
            expected: issue === undefined ? '' : issue.expected,
            actualType: issue === undefined ? '' : issue.actualType,
          });
        }
        return { status: LegacyReadStatus.INVALID, values: null };
      }
    }
    return LegacyPreferencesReader.toStringList(value);
  }

  async readPersonalized(): Promise<LegacyPersonalizedResult> {
    const raw = await this.readRaw(LegacyStorageKeys.PERSONALIZED_STORE, LegacyStorageKeys.PERSONALIZED_KEY);
    if (raw.status !== LegacyReadStatus.VALUE) {
      return { status: raw.status, enabled: null, lastChangedAt: null };
    }
    const value = raw.value;
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      return { status: LegacyReadStatus.INVALID, enabled: null, lastChangedAt: null };
    }
    const parsed = value as LegacyPersonalizedValue;
    if (typeof parsed.enablePersonalized !== 'boolean') {
      return { status: LegacyReadStatus.INVALID, enabled: null, lastChangedAt: null };
    }
    return {
      status: LegacyReadStatus.VALUE,
      enabled: parsed.enablePersonalized,
      lastChangedAt: StorageTime.parseLegacyDate(parsed.updateDate === undefined ? null : parsed.updateDate)
    };
  }

  async readDouyinCacheTimestamp(): Promise<LegacyTimestampResult> {
    try {
      const records: DouYinCacheRecords | undefined = PersistenceV2.connect(
        DouYinCacheRecords,
        LegacyStorageKeys.DOUYIN_CACHE_PERSISTENCE_V2_KEY,
        () => new DouYinCacheRecords());
      if (records === undefined || records.jingxuanRecordOrNull === null) {
        return { status: LegacyReadStatus.MISSING, timestamp: null };
      }
      const timestamp = StorageTime.parseLegacyDate(records.jingxuanRecordOrNull.lastCacheDate);
      if (timestamp === null) {
        return { status: LegacyReadStatus.INVALID, timestamp: null };
      }
      return { status: LegacyReadStatus.VALUE, timestamp: timestamp };
    } catch (_) {
      return { status: LegacyReadStatus.ERROR, timestamp: null };
    }
  }

  private async readBooleanFlag(storeName: string, key: string): Promise<LegacyBooleanResult> {
    const raw = await this.readRaw(storeName, key);
    if (raw.status !== LegacyReadStatus.VALUE) {
      return { status: raw.status, value: null };
    }
    const value = raw.value;
    if (typeof value === 'boolean') {
      return { status: LegacyReadStatus.VALUE, value: value };
    }
    if (typeof value === 'string') {
      const normalized = value.trim();
      if (normalized === 'true') {
        return { status: LegacyReadStatus.VALUE, value: true };
      }
      if (normalized === 'false') {
        return { status: LegacyReadStatus.VALUE, value: false };
      }
    }
    return { status: LegacyReadStatus.INVALID, value: null };
  }

  private async readRaw(storeName: string, key: string): Promise<LegacyRawResult> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, storeName);
      if (!(await store.has(key))) {
        return { status: LegacyReadStatus.MISSING, value: null };
      }
      const value: preferences.ValueType = await store.get(key, '');
      return { status: LegacyReadStatus.VALUE, value: value };
    } catch (_) {
      return { status: LegacyReadStatus.ERROR, value: null };
    }
  }

  private static toStringList(value: preferences.ValueType | null): LegacyStringListResult {
    if (!Array.isArray(value)) {
      return { status: LegacyReadStatus.INVALID, values: null };
    }
    const source: Object[] = value as Object[];
    const result: string[] = [];
    for (const item of source) {
      if (typeof item !== 'string') {
        return { status: LegacyReadStatus.INVALID, values: null };
      }
      result.push(item);
    }
    return { status: LegacyReadStatus.VALUE, values: result };
  }
}
