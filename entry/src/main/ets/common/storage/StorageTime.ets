/** 可注入的时钟，便于主机测试固定时间。 */
export interface StorageClock {
  nowIso(): string;
}

export class SystemStorageClock implements StorageClock {
  nowIso(): string {
    return new Date().toISOString();
  }
}

export class StorageTime {
  /** 新写入时间：ISO-8601 UTC，毫秒精度。 */
  static nowIso(): string {
    return new Date().toISOString();
  }

  /** 只接受规范 ISO-8601 UTC（与 Date#toISOString 完全一致）。 */
  static isCanonicalIso(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    const milliseconds = Date.parse(value);
    if (isNaN(milliseconds)) {
      return false;
    }
    return new Date(milliseconds).toISOString() === value;
  }

  /**
   * 值发生变化时的时间：若系统时钟回拨到首次存储之前，保持 last >= first。
   */
  static clampChangedAt(firstStoredAt: string, now: string): string {
    if (!StorageTime.isCanonicalIso(firstStoredAt)) {
      return now;
    }
    return now >= firstStoredAt ? now : firstStoredAt;
  }

  /** 旧 preferences 的 Date / 时间字符串 / 毫秒数 → 规范 ISO；无法解析返回 null。 */
  static parseLegacyDate(value: Object | null): string | null {
    if (value === null) {
      return null;
    }
    if (value instanceof Date) {
      const milliseconds = value.getTime();
      return isNaN(milliseconds) ? null : new Date(milliseconds).toISOString();
    }
    if (typeof value === 'number') {
      return isNaN(value) ? null : new Date(value).toISOString();
    }
    if (typeof value === 'string') {
      const milliseconds = Date.parse(value);
      return isNaN(milliseconds) ? null : new Date(milliseconds).toISOString();
    }
    return null;
  }

  /** 迁移时不让旧时间戳跑到未来。 */
  static clampToNow(iso: string | null, now: string): string {
    if (iso === null || !StorageTime.isCanonicalIso(iso)) {
      return now;
    }
    return iso > now ? now : iso;
  }
}
