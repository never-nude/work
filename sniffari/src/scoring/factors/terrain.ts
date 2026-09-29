import type { EdgeFactor } from '../../types';

/** Grade (%) → score breakpoints, linearly interpolated. */
const CURVE: [number, number][] = [
  [2, 1],
  [5, 0.6],
  [8, 0.3],
  [12, 0.05],
];

export function gradeScore(g: number): number {
  if (g <= CURVE[0]![0]) return CURVE[0]![1];
  for (let i = 1; i < CURVE.length; i++) {
    const [g1, s1] = CURVE[i]!;
    if (g <= g1) {
      const [g0, s0] = CURVE[i - 1]!;
      return s0 + ((s1 - s0) * (g - g0)) / (g1 - g0);
    }
  }
  return CURVE[CURVE.length - 1]![1];
}

/** Factor 12 — how hilly. Flat is best; stairs are hard work whatever the DEM says. */
export const terrain: EdgeFactor = (f) => {
  if (f.roadClass === 'steps') return { score: 0.3, reason: 'Stairs' };
  if (f.gradePct === null) return { score: 0.8, reason: 'Elevation unavailable' };
  const g = f.gradePct;
  const s = gradeScore(g);
  const pct = g < 1 ? '<1' : g.toFixed(g < 10 ? 1 : 0);
  const label = g <= 2 ? 'Flat' : g <= 5 ? 'Gentle slope' : g <= 8 ? 'Hilly' : 'Steep';
  return { score: s, reason: `${label} (${pct}% grade)` };
};
