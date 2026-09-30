import type { EdgeFactor } from '../../types';
import { clamp01, metres } from './util';

/** How busy commercial areas are at a given hour, relative to midday baseline. */
export function crowdMultiplier(hour: number): number {
  if (hour >= 22 || hour < 6) return 0.5;
  if (hour >= 7 && hour < 9) return 1.2; // morning rush
  if (hour >= 11 && hour < 14) return 1.3; // lunch
  if (hour >= 17 && hour < 21) return 1.4; // evening rush + dinner
  return 1;
}

/** Commercial POIs per 100 m at which a street counts as fully crowded. */
const SATURATION = 10;

/** Factor 6 — people, shops, patios, transit. Scaled by time of day. */
export const crowds: EdgeFactor = (f, ctx) => {
  const density = (f.commercialPer100m * crowdMultiplier(ctx.hour)) / SATURATION;
  let s = 1 - Math.min(1, density);
  const reasons: string[] = [];
  if (f.commercialPer100m >= 6) reasons.push('Dense shops and restaurants');
  else if (f.commercialPer100m >= 2) reasons.push('Some shops and restaurants');
  if (f.distStationM < 200) {
    s *= 0.7;
    reasons.push(`station ${metres(f.distStationM)} away`);
  } else if (f.distStationM < 400) {
    s *= 0.9;
  }
  if (f.busStops > 0) {
    s -= 0.05 * f.busStops;
    reasons.push(f.busStops === 1 ? 'bus stop' : `${f.busStops} bus stops`);
  }
  s = clamp01(s);
  if (reasons.length === 0) reasons.push('Few people expected');
  const text = reasons.join(', ');
  return { score: s, reason: text.charAt(0).toUpperCase() + text.slice(1) };
};
