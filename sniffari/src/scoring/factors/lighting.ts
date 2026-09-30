import type { EdgeFactor, RoadClass } from '../../types';

const PROBABLY_LIT: ReadonlySet<RoadClass> = new Set([
  'residential', 'unclassified', 'tertiary', 'secondary', 'primary', 'living_street', 'pedestrian', 'service',
]);

/** Factor 8 — street lighting. Profiles only weight this after sunset. */
export const lighting: EdgeFactor = (f) => {
  if (f.lit === 'yes') return { score: 1, reason: 'Lit' };
  if (f.lit === 'no') return { score: 0.1, reason: 'Unlit' };
  if (f.footwayType === 'sidewalk') return { score: 0.75, reason: 'Probably lit (street sidewalk)' };
  if (PROBABLY_LIT.has(f.roadClass)) return { score: 0.7, reason: 'Probably lit (lighting not mapped)' };
  return { score: 0.35, reason: 'Lighting unknown (path)' };
};
