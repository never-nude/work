import type { LngLat, Route } from '../types';
import { haversineM } from '../graph/geo';

/** Google Maps directions URLs accept at most 9 waypoints; keep one spare for safety across platforms. */
export const MAX_GOOGLE_WAYPOINTS = 8;

const fmt = ([lon, lat]: LngLat) => `${lat.toFixed(6)},${lon.toFixed(6)}`;

/**
 * Pick waypoints that pin Google's walking directions to our path: prefer the
 * sharpest turns (where Google would otherwise take a different street), then
 * fill gaps so no stretch between pins is long. Returns indices into coords.
 */
export function pickWaypoints(coords: LngLat[], max = MAX_GOOGLE_WAYPOINTS): number[] {
  if (coords.length < 3) return [];
  const cum: number[] = [0];
  for (let i = 1; i < coords.length; i++) {
    const [a, b] = [coords[i - 1]!, coords[i]!];
    cum.push(cum[i - 1]! + haversineM({ lat: a[1], lon: a[0] }, { lat: b[1], lon: b[0] }));
  }
  const total = cum[cum.length - 1]!;
  if (total === 0) return [];

  // Even spacing by distance is the backbone (a loop needs points all the way round
  // or Google shortcuts back the way it came); each slot then snaps to the sharpest
  // turn within its stretch so the pin lands on a corner, not mid-block.
  const out: number[] = [];
  for (let k = 1; k <= max; k++) {
    const lo = (total * (k - 0.5)) / (max + 1);
    const hi = (total * (k + 0.5)) / (max + 1);
    let best = -1;
    let bestTurn = -1;
    for (let i = 1; i < coords.length - 1; i++) {
      if (cum[i]! < lo || cum[i]! > hi) continue;
      const t = turnAngle(coords[i - 1]!, coords[i]!, coords[i + 1]!);
      if (t > bestTurn) {
        bestTurn = t;
        best = i;
      }
    }
    if (best < 0) {
      // No vertex in this stretch: nearest vertex to the slot's centre.
      const target = (total * k) / (max + 1);
      let d = Infinity;
      for (let i = 1; i < coords.length - 1; i++) {
        const dd = Math.abs(cum[i]! - target);
        if (dd < d) {
          d = dd;
          best = i;
        }
      }
    }
    if (best > 0 && !out.includes(best)) out.push(best);
  }
  return out.sort((a, b) => a - b);
}

function turnAngle(a: LngLat, b: LngLat, c: LngLat): number {
  const h1 = Math.atan2(b[1] - a[1], b[0] - a[0]);
  const h2 = Math.atan2(c[1] - b[1], c[0] - b[0]);
  let d = Math.abs(h2 - h1);
  if (d > Math.PI) d = 2 * Math.PI - d;
  return d;
}

/**
 * Google Maps walking directions following the route. Opens the Google Maps
 * app on iPhone when installed (universal link), the website otherwise.
 * Google re-computes the path between waypoints, so it's a close — not exact — match.
 */
export function googleMapsUrl(route: Route): string {
  const c = route.coords;
  const params = new URLSearchParams({
    api: '1',
    origin: fmt(c[0]!),
    destination: fmt(c[c.length - 1]!),
    travelmode: 'walking',
  });
  const wps = pickWaypoints(c).map((i) => fmt(c[i]!));
  if (wps.length) params.set('waypoints', wps.join('|'));
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}

/**
 * Apple Maps walking directions from the route's start to its finish. Apple's
 * URL format takes no intermediate stops, so it picks its own streets — only
 * meaningful for one-way walks (a loop's start and finish are the same point).
 */
export function appleMapsUrl(route: Route): string {
  const c = route.coords;
  const params = new URLSearchParams({ saddr: fmt(c[0]!), daddr: fmt(c[c.length - 1]!), dirflg: 'w' });
  return `https://maps.apple.com/?${params.toString()}`;
}

/** GPX track — the exact path, for Strava, Gaia, AllTrails, Komoot, etc. */
export function toGpx(route: Route, name = 'Sniffari walk'): string {
  const esc = (s: string) => s.replace(/[<>&"]/g, (ch) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' })[ch]!);
  const pts = route.coords.map(([lon, lat]) => `      <trkpt lat="${lat.toFixed(7)}" lon="${lon.toFixed(7)}"/>`).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Sniffari" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${esc(name)}</name><desc>${esc(route.why)}</desc></metadata>
  <trk>
    <name>${esc(name)}</name>
    <trkseg>
${pts}
    </trkseg>
  </trk>
</gpx>
`;
}
