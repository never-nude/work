import { describe, expect, it, vi } from 'vitest';
import { TTLCache, memoryStore } from './cache';
import { bboxAround, buildQuery, fetchOverpass, tilesForBBox, TILE_DEG } from './overpass';

describe('tiles', () => {
  it('covers the bbox with a fixed grid', () => {
    const bb = bboxAround({ lat: 41.0335, lon: -73.763 }, 2800);
    const tiles = tilesForBBox(bb);
    expect(tiles.length).toBeGreaterThanOrEqual(9);
    expect(tiles.length).toBeLessThanOrEqual(20);
    for (const t of tiles) {
      expect(t.bbox[2] - t.bbox[0]).toBeCloseTo(TILE_DEG);
    }
    // stable keys → cache hits across sessions
    expect(tilesForBBox(bb).map((t) => t.key)).toEqual(tiles.map((t) => t.key));
  });
});

describe('buildQuery', () => {
  it('puts the bbox on every statement and pulls road nodes with tags', () => {
    const q = buildQuery([41, -74, 41.02, -73.98]);
    expect(q).toContain('(41,-74,41.02,-73.98)');
    expect(q).toContain('node(w.roads);\nout body qt;');
    expect(q).not.toContain('[bbox:');
  });
});

describe('fetchOverpass', () => {
  it('falls back to the next endpoint on failure', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(new Response('nope', { status: 500 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ elements: [] }), { status: 200 }));
    const r = await fetchOverpass('q', { endpoints: ['a', 'b'], fetchImpl: fetchImpl as unknown as typeof fetch });
    expect(r.elements).toEqual([]);
    expect(fetchImpl.mock.calls.map((c) => c[0])).toEqual(['a', 'b']);
  });
});

describe('fetchOverpass timeout', () => {
  it('fails over to the next endpoint when one hangs', async () => {
    const fetchImpl = vi.fn((url: string, init: RequestInit) =>
      url === 'slow'
        ? new Promise<Response>((_, reject) => init.signal!.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' }))))
        : Promise.resolve(new Response(JSON.stringify({ elements: [1] }), { status: 200 })),
    );
    const r = await fetchOverpass('q', { endpoints: ['slow', 'fast'], fetchImpl: fetchImpl as unknown as typeof fetch, timeoutMs: 50 });
    expect(r.elements).toEqual([1]);
  });
});

describe('TTLCache', () => {
  it('expires entries after the TTL', async () => {
    let now = 0;
    const c = new TTLCache(memoryStore(), 1000, () => now);
    const fetcher = vi.fn(async () => 'v');
    expect(await c.getOrFetch('k', fetcher)).toEqual({ value: 'v', hit: false });
    now = 500;
    expect(await c.getOrFetch('k', fetcher)).toEqual({ value: 'v', hit: true });
    now = 2000;
    expect(await c.getOrFetch('k', fetcher)).toEqual({ value: 'v', hit: false });
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});
