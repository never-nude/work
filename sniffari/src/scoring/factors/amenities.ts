import type { AmenityCounts, EdgeFactor } from '../../types';
import { clamp01 } from './util';

const VALUE: Record<keyof AmenityCounts, number> = {
  wasteBaskets: 0.5,
  bagDispensers: 0.7,
  dogWater: 0.8,
  water: 0.4,
  benches: 0.25,
  dogFriendly: 0.3,
};

const LABEL: Record<keyof AmenityCounts, [string, string]> = {
  wasteBaskets: ['bin', 'bins'],
  bagDispensers: ['bag dispenser', 'bag dispensers'],
  dogWater: ['dog water fountain', 'dog water fountains'],
  water: ['water fountain', 'water fountains'],
  benches: ['bench', 'benches'],
  dogFriendly: ['dog-friendly spot', 'dog-friendly spots'],
};

/** Factor 9 — bonus for bins, bags, water, benches and dog-friendly businesses. Not weighted; additive at route level. */
export const amenities: EdgeFactor = (f) => {
  let s = 0;
  const parts: string[] = [];
  for (const k of Object.keys(VALUE) as (keyof AmenityCounts)[]) {
    const n = f.amenities[k];
    if (n <= 0) continue;
    s += VALUE[k] * Math.min(n, 3);
    parts.push(`${n} ${LABEL[k][n === 1 ? 0 : 1]}`);
  }
  return { score: clamp01(s), reason: parts.length ? parts.join(', ') : 'No amenities mapped' };
};
