import type { LatLon, LngLat, Maneuver } from '../types';

/** Cumulative metres along a polyline, for progress tracking. */
export function cumulative(coords: LngLat[]): number[] {
  const out = [0];
  for (let i = 1; i < coords.length; i++) out.push(out[i - 1]! + segLen(coords[i - 1]!, coords[i]!));
  return out;
}

function segLen(a: LngLat, b: LngLat): number {
  const k = 111_320 * Math.cos((a[1] * Math.PI) / 180);
  return Math.hypot((b[0] - a[0]) * k, (b[1] - a[1]) * 110_574);
}

export interface Progress {
  /** Metres walked along the route. */
  alongM: number;
  /** How far the walker is from the route line. */
  offM: number;
}

/**
 * Project the walker onto the route. Searches forward from the last known
 * position first (so a loop's return leg isn't confused with its start),
 * falling back to the whole route if they're far from that window.
 */
export function project(coords: LngLat[], cum: number[], p: LatLon, lastAlongM = 0): Progress {
  const kx = 111_320 * Math.cos((p.lat * Math.PI) / 180);
  const ky = 110_574;
  const best = (from: number, to: number) => {
    let b = { alongM: 0, offM: Infinity };
    for (let i = Math.max(1, from); i < Math.min(coords.length, to); i++) {
      const a = coords[i - 1]!, c = coords[i]!;
      const ax = (a[0] - p.lon) * kx, ay = (a[1] - p.lat) * ky;
      const cx = (c[0] - p.lon) * kx, cy = (c[1] - p.lat) * ky;
      const dx = cx - ax, dy = cy - ay;
      const l2 = dx * dx + dy * dy;
      const t = l2 === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / l2));
      const off = Math.hypot(ax + t * dx, ay + t * dy);
      if (off < b.offM) b = { offM: off, alongM: cum[i - 1]! + t * Math.sqrt(l2) };
    }
    return b;
  };
  // Window: from a little behind the last position to 400 m ahead.
  let lo = 1;
  while (lo < cum.length - 1 && cum[lo]! < lastAlongM - 50) lo++;
  let hi = lo;
  while (hi < cum.length && cum[hi]! < lastAlongM + 400) hi++;
  const near = best(lo, hi + 1);
  if (near.offM <= 40) return near;
  const all = best(1, coords.length);
  return all.offM < near.offM ? all : near;
}

/** The next instruction ahead of the walker, and the distance to it. */
export function nextManeuver(maneuvers: Maneuver[], alongM: number): { m: Maneuver; inM: number } | null {
  for (const m of maneuvers) {
    if (m.kind === 'start') continue;
    if (m.atM > alongM - 5) return { m, inM: Math.max(0, m.atM - alongM) };
  }
  return null;
}
