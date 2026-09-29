import type { EdgeFactor } from '../../types';
import { clamp01, metres, pct } from './util';

/**
 * Factor 3 — sniffable green. OSM maps parks well but rarely maps front lawns
 * or tree-lawn verges, so residential streets get a small baseline instead of 0.
 */
export const grass: EdgeFactor = (f) => {
  if (f.grassFraction >= 0.05) {
    const s = clamp01(0.25 + f.grassFraction * 0.75);
    return { score: s, reason: `${pct(f.grassFraction)} of this stretch borders grass or park` };
  }
  let s = 0;
  let reason = 'No mapped grass nearby';
  if (f.nearGrassM <= 80) {
    s = 0.25;
    reason = `Grass ${metres(f.nearGrassM)} away`;
  } else if (f.nearGrassM <= 200) {
    s = 0.1;
    reason = `Grass ${metres(f.nearGrassM)} away`;
  }
  if (f.roadClass === 'residential' || f.roadClass === 'living_street') {
    if (s < 0.3) {
      s = 0.3;
      reason = 'Likely lawns and verges (not mapped)';
    }
  }
  return { score: s, reason };
};
