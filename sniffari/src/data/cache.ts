import { get, set, del } from 'idb-keyval';

export const DEFAULT_TTL_MS = 7 * 24 * 60 * 60 * 1000;

interface Entry<T> {
  savedAt: number;
  value: T;
}

/** Minimal async KV so tests can swap IndexedDB for a Map. */
export interface KVStore {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown): Promise<void>;
  del(key: string): Promise<void>;
}

export const idbStore: KVStore = { get: (k) => get(k), set: (k, v) => set(k, v), del: (k) => del(k) };

export function memoryStore(): KVStore {
  const m = new Map<string, unknown>();
  return {
    get: async (k) => m.get(k),
    set: async (k, v) => void m.set(k, v),
    del: async (k) => void m.delete(k),
  };
}

export class TTLCache {
  constructor(
    private readonly store: KVStore = idbStore,
    private readonly ttlMs = DEFAULT_TTL_MS,
    private readonly now: () => number = Date.now,
  ) {}

  async get<T>(key: string): Promise<T | undefined> {
    try {
      const e = (await this.store.get(key)) as Entry<T> | undefined;
      if (!e) return undefined;
      if (this.now() - e.savedAt > this.ttlMs) {
        await this.store.del(key);
        return undefined;
      }
      return e.value;
    } catch {
      return undefined; // private mode / storage blocked: behave as a miss
    }
  }

  async set<T>(key: string, value: T): Promise<void> {
    try {
      await this.store.set(key, { savedAt: this.now(), value } satisfies Entry<T>);
    } catch {
      /* quota or blocked storage — caching is best-effort */
    }
  }

  /** Cached value, or compute + store it. */
  async getOrFetch<T>(key: string, fetcher: () => Promise<T>): Promise<{ value: T; hit: boolean }> {
    const cached = await this.get<T>(key);
    if (cached !== undefined) return { value: cached, hit: true };
    const value = await fetcher();
    await this.set(key, value);
    return { value, hit: false };
  }
}
