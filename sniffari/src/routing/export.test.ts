import { describe, expect, it } from 'vitest';
import type { LngLat, Route } from '../types';
import { appleMapsUrl, googleMapsUrl, MAX_GOOGLE_WAYPOINTS, pickWaypoints, toGpx } from './export';

// A square loop ~400 m a side with intermediate vertices.
const sq: LngLat[] = [];
const d = 0.0036;
const corners: LngLat[] = [[0, 0], [d, 0], [d, d], [0, d], [0, 0]];
for (let k = 0; k < 4; k++) {
  const [a, b] = [corners[k]!, corners[k + 1]!];
  for (let i = 0; i < 5; i++) sq.push([-73.76 + a[0] + ((b[0] - a[0]) * i) / 5, 41.03 + a[1] + ((b[1] - a[1]) * i) / 5]);
}
sq.push(sq[0]!);
const route = { coords: sq, why: 'Quiet & green <test>' } as Route;

describe('google maps export', () => {
  it('uses at most 8 waypoints and includes the corners', () => {
    const w = pickWaypoints(sq);
    expect(w.length).toBeLessThanOrEqual(MAX_GOOGLE_WAYPOINTS);
    // corners are at indices 5, 10, 15
    for (const c of [5, 10, 15]) expect(w).toContain(c);
  });
  it('builds a walking directions URL that starts and ends at the start for a loop', () => {
    const u = new URL(googleMapsUrl(route));
    expect(u.origin + u.pathname).toBe('https://www.google.com/maps/dir/');
    expect(u.searchParams.get('travelmode')).toBe('walking');
    expect(u.searchParams.get('origin')).toBe(u.searchParams.get('destination'));
    expect(u.searchParams.get('waypoints')!.split('|').length).toBeLessThanOrEqual(8);
  });
});

describe('gpx export', () => {
  it('writes every point and escapes text', () => {
    const g = toGpx(route);
    expect(g.match(/<trkpt /g)!.length).toBe(sq.length);
    expect(g).toContain('Quiet &amp; green &lt;test&gt;');
  });
});

describe('apple maps export', () => {
  it('is walking directions from start to finish', () => {
    const oneWay = { coords: sq.slice(0, 11), why: '' } as Route;
    const u = new URL(appleMapsUrl(oneWay));
    expect(u.host).toBe('maps.apple.com');
    expect(u.searchParams.get('dirflg')).toBe('w');
    expect(u.searchParams.get('saddr')).not.toBe(u.searchParams.get('daddr'));
  });
});
