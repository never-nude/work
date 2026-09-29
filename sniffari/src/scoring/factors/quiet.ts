import type { EdgeFactor, RoadClass } from '../../types';
import { clamp01 } from './util';

const BASE: Partial<Record<RoadClass, number>> = {
  pedestrian: 1,
  footway: 1,
  path: 1,
  steps: 1,
  living_street: 1,
  residential: 1,
  track: 1,
  service: 0.9,
  cycleway: 0.9,
  unclassified: 0.85,
  tertiary: 0.6,
  secondary: 0.3,
  primary: 0.1,
  trunk: 0,
  motorway: 0,
};

const LABEL: Partial<Record<RoadClass, string>> = {
  tertiary: 'Moderate traffic',
  secondary: 'Busy road',
  primary: 'Very busy arterial',
  trunk: 'Highway',
  motorway: 'Highway',
};

/** Factor 2 — traffic noise and stress, from road class plus nearby major roads and rail. */
export const quiet: EdgeFactor = (f) => {
  let s = BASE[f.roadClass] ?? 0.8;
  const reasons: string[] = [];
  const label = LABEL[f.roadClass];
  if (label) reasons.push(label);

  if (f.maxspeedMph !== null && f.maxspeedMph >= 45) {
    s *= 0.5;
    reasons.push(`${f.maxspeedMph} mph traffic`);
  } else if (f.maxspeedMph !== null && f.maxspeedMph > 35) {
    s *= 0.7;
    reasons.push(`${f.maxspeedMph} mph traffic`);
  }
  if (f.lanes !== null && f.lanes >= 4) {
    s *= 0.8;
    reasons.push(`${f.lanes} lanes`);
  }

  // Being next to a major road is loud even on a footpath (sidewalks of Main St).
  if (f.distMajorRoadM < 25) {
    s = Math.min(s, 0.35);
    reasons.push('right beside a major road');
  } else if (f.distMajorRoadM < 60) {
    s *= 0.7;
    reasons.push('near a major road');
  } else if (f.distMajorRoadM < 120) {
    s *= 0.9;
  }

  if (f.distRailM < 50) {
    s *= 0.7;
    reasons.push('next to the railway');
  } else if (f.distRailM < 150) {
    s *= 0.9;
    reasons.push('near the railway');
  }

  s = clamp01(s);
  if (reasons.length === 0) reasons.push(s >= 0.9 ? 'Quiet street' : 'Some traffic');
  const text = reasons.join(', ');
  return { score: s, reason: text.charAt(0).toUpperCase() + text.slice(1) };
};
