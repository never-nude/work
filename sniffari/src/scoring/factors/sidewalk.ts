import type { EdgeFactor, RoadClass } from '../../types';

const DEDICATED: Partial<Record<RoadClass, [number, string]>> = {
  pedestrian: [1, 'Pedestrian street'],
  footway: [1, 'Footpath'],
  path: [0.9, 'Path'],
  living_street: [0.9, 'Shared living street'],
  steps: [0.6, 'Steps'],
};

/** When sidewalks are simply not mapped, guess from road class. */
const UNKNOWN_BY_CLASS: Partial<Record<RoadClass, number>> = {
  residential: 0.75,
  unclassified: 0.65,
  service: 0.55,
  tertiary: 0.6,
  secondary: 0.5,
  primary: 0.45,
};

/** Factor 1 — is there somewhere safe to walk? */
export const sidewalk: EdgeFactor = (f) => {
  if (f.sidewalk === 'dedicated') {
    if (f.footwayType === 'sidewalk') return { score: 1, reason: 'Sidewalk' };
    if (f.footwayType === 'crossing') return { score: 0.9, reason: 'Crosswalk' };
    const d = DEDICATED[f.roadClass];
    if (d) return { score: d[0], reason: d[1] };
    return { score: 0.9, reason: 'Footpath' };
  }
  switch (f.sidewalk) {
    case 'both':
      return { score: 1, reason: 'Sidewalks both sides' };
    case 'separate':
      return { score: 0.9, reason: 'Sidewalk mapped separately' };
    case 'one':
      return { score: 0.8, reason: 'Sidewalk one side' };
    case 'none': {
      const slow = f.maxspeedMph !== null && f.maxspeedMph <= 25;
      if (['residential', 'service', 'unclassified', 'track'].includes(f.roadClass)) {
        return { score: slow ? 0.55 : 0.5, reason: 'No sidewalk (quiet road)' };
      }
      if (f.roadClass === 'cycleway') return { score: 0.5, reason: 'Bike path, no sidewalk' };
      return { score: 0.2, reason: 'No sidewalk on a through road' };
    }
    default: {
      if (f.roadClass === 'cycleway') return { score: f.foot === 'designated' || f.foot === 'yes' ? 0.8 : 0.6, reason: 'Shared bike path' };
      if (f.roadClass === 'track') return { score: 0.6, reason: 'Track' };
      const s = UNKNOWN_BY_CLASS[f.roadClass] ?? 0.5;
      return { score: s, reason: 'Sidewalk not mapped' };
    }
  }
};
