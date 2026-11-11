export class TimedCacheValue<T> {
  value: T;
  expiresAt: number;
  weight: number;
  constructor(value: T, expiresAt: number, weight: number) {
    this.value = value; this.expiresAt = expiresAt; this.weight = weight;
  }
}

/** Bounded stale-while-revalidate cache. Refuse oversized entries; never truncate their content. */
export class TimedMemoryCache<T> {
  private entries: Map<string, TimedCacheValue<T>> = new Map();
  private weight: number = 0;
  private maxEntries: number;
  private maxWeight: number;
  private ttl: number;
  constructor(maxEntries: number, maxWeight: number, ttl: number) {
    this.maxEntries = maxEntries; this.maxWeight = maxWeight; this.ttl = ttl;
  }

  get(key: string): TimedCacheValue<T> | undefined {
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      this.entries.delete(key);
      this.entries.set(key, entry);
    }
    return entry;
  }

  put(key: string, value: T, weight: number, now: number = Date.now()): void {
    this.remove(key);
    if (!Number.isFinite(weight) || weight < 0 || weight > this.maxWeight || this.maxEntries <= 0) { return; }
    this.entries.set(key, new TimedCacheValue(value, now + this.ttl, weight));
    this.weight += weight;
    while (this.entries.size > this.maxEntries || this.weight > this.maxWeight) {
      const oldest = this.entries.keys().next().value as string;
      this.remove(oldest);
    }
  }

  private remove(key: string): void {
    const previous = this.entries.get(key);
    if (previous !== undefined) { this.weight -= previous.weight; this.entries.delete(key); }
  }
}
