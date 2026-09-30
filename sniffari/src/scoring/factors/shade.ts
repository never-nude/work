import type { EdgeFactor } from '../../types';
import { clamp01, pct } from './util';

/** Trees per 100 m that we treat as "fully shaded". */
const FULL_SHADE_TREES = 8;

/** Factor 4 — shade from mapped trees, tree rows and woodland. */
export const shade: EdgeFactor = (f) => {
  const fromTrees = Math.min(1, f.treesPer100m / FULL_SHADE_TREES);
  const fromCanopy = f.canopyFraction;
  const s = clamp01(Math.max(fromTrees, fromCanopy) + 0.3 * Math.min(fromTrees, fromCanopy));
  if (s === 0) return { score: 0, reason: 'No mapped trees' };
  if (fromCanopy >= fromTrees) return { score: s, reason: `${pct(fromCanopy)} under woodland or tree rows` };
  const n = Math.round(f.treesPer100m * 10) / 10;
  return { score: s, reason: `${n} street trees per 100 m` };
};
