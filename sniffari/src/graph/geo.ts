import type { LatLon, LngLat } from '../types';

const M_PER_DEG_LAT = 110_574;
const M_PER_DEG_LON_EQ = 111_320;

/**
 * Equirectangular projection around a fixed origin. Error is well under 1%
 * within a few km, which is all a walk ever covers — and it keeps every
 * spatial query in plain metres.
 */
export interface Projection {
  origin: LatLon;
  toXY(lat: number, lon: number): [number, number];
  toLatLon(x: number, y: number): LatLon;
}

export function makeProjection(origin: LatLon): Projection {
  const kx = M_PER_DEG_LON_EQ * Math.cos((origin.lat * Math.PI) / 180);
  const ky = M_PER_DEG_LAT;
  return {
    origin,
    toXY: (lat, lon) => [(lon - origin.lon) * kx, (lat - origin.lat) * ky],
    toLatLon: (x, y) => ({ lat: origin.lat + y / ky, lon: origin.lon + x / kx }),
  };
}

export function haversineM(a: LatLon, b: LatLon): number {
  const R = 6_371_008.8;
  const toRad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * toRad;
  const dLon = (b.lon - a.lon) * toRad;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * toRad) * Math.cos(b.lat * toRad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

export function polylineLengthXY(pts: [number, number][]): number {
  let len = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1]!;
    const b = pts[i]!;
    len += Math.hypot(b[0] - a[0], b[1] - a[1]);
  }
  return len;
}

/** Evenly spaced samples along a polyline, always including both ends. */
export function samplePolyline(pts: [number, number][], spacingM: number): [number, number][] {
  if (pts.length === 0) return [];
  if (pts.length === 1) return [pts[0]!];
  const total = polylineLengthXY(pts);
  const n = Math.max(2, Math.ceil(total / spacingM) + 1);
  const step = total / (n - 1);
  const out: [number, number][] = [];
  let seg = 0;
  let segStart = 0; // distance along the line at the start of `seg`
  for (let i = 0; i < n; i++) {
    const target = Math.min(total, i * step);
    while (seg < pts.length - 2) {
      const a = pts[seg]!;
      const b = pts[seg + 1]!;
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (segStart + l >= target) break;
      segStart += l;
      seg++;
    }
    const a = pts[seg]!;
    const b = pts[seg + 1]!;
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const t = l === 0 ? 0 : Math.min(1, Math.max(0, (target - segStart) / l));
    out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
  }
  return out;
}

export function pointSegmentDist(
  px: number,
  py: number,
  ax: number,
  ay: number,
  bx: number,
  by: number,
): number {
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

/** Ray-casting point-in-ring. Ring may or may not repeat its first point. */
export function pointInRing(px: number, py: number, ring: [number, number][]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]!;
    const [xj, yj] = ring[j]!;
    if (yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function median(values: number[]): number {
  if (values.length === 0) return Infinity;
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

export function toLngLat(p: LatLon): LngLat {
  return [p.lon, p.lat];
}
