import type { LatLon, LngLat } from '../types';
import { haversineM } from '../graph/geo';

/** Radius around a walk's start and finish that friends never see (usually someone's front door). */
export const PRIVACY_RADIUS_M = 150;

const ll = ([lon, lat]: LngLat): LatLon => ({ lat, lon });

/** The route friends see: everything outside the privacy radius of its start and end. */
export function publicRoute(coords: LngLat[], radiusM = PRIVACY_RADIUS_M): LngLat[] {
  if (coords.length < 2) return [];
  const start = ll(coords[0]!);
  const end = ll(coords[coords.length - 1]!);
  return coords.filter((c) => haversineM(ll(c), start) > radiusM && haversineM(ll(c), end) > radiusM);
}

/** Only publish the walker's live position when they're outside both privacy zones. */
export function mayPublishPosition(me: LatLon, coords: LngLat[], radiusM = PRIVACY_RADIUS_M): boolean {
  if (coords.length < 2) return false;
  return haversineM(me, ll(coords[0]!)) > radiusM && haversineM(me, ll(coords[coords.length - 1]!)) > radiusM;
}

/** Rate-limits position uploads: at most every `minMs`, and only after moving `minM`. */
export function makePositionGate(minMs = 15_000, minM = 20) {
  let lastAt = 0;
  let last: LatLon | null = null;
  return (p: LatLon, now = Date.now()): boolean => {
    if (last && now - lastAt < minMs) return false;
    if (last && haversineM(last, p) < minM) return false;
    lastAt = now;
    last = p;
    return true;
  };
}
