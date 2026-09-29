import type { EdgeFactor } from '../../types';

/**
 * Factor 7 — paved vs unpaved. Neutral-ish without weather; Phase 4 weather
 * flips it: heat favours unpaved (paw-safe), recent rain penalises it (mud).
 */
export const surface: EdgeFactor = (f, ctx) => {
  const w = ctx.weather;
  const hot = w !== undefined && w.tempF >= 77;
  const wet = w !== undefined && w.precipLast24hMm >= 5;
  switch (f.surface) {
    case 'paved':
      if (hot) return { score: 0.5, reason: 'Pavement — hot underfoot' };
      return { score: 0.9, reason: 'Paved' };
    case 'unpaved':
      if (wet) return { score: 0.3, reason: 'Unpaved — likely muddy' };
      if (hot) return { score: 1, reason: 'Unpaved — cooler on paws' };
      return { score: 0.85, reason: 'Unpaved' };
    default:
      return { score: 0.8, reason: 'Surface unknown' };
  }
};
