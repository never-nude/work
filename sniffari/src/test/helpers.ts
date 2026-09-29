import type { EdgeFeatures, ScoringContext } from '../types';

export function makeFeatures(over: Partial<EdgeFeatures> = {}): EdgeFeatures {
  return {
    highway: 'residential',
    roadClass: 'residential',
    footwayType: null,
    service: null,
    sidewalk: 'both',
    maxspeedMph: null,
    lanes: null,
    foot: null,
    access: null,
    dog: null,
    construction: false,
    surface: 'paved',
    lit: 'unknown',
    distMajorRoadM: 1000,
    distRailM: 1000,
    grassFraction: 0,
    nearGrassM: 1000,
    treesPer100m: 0,
    canopyFraction: 0,
    commercialPer100m: 0,
    distStationM: 1000,
    busStops: 0,
    amenities: { wasteBaskets: 0, bagDispensers: 0, water: 0, dogWater: 0, benches: 0, dogFriendly: 0 },
    ...over,
  };
}

export const NOON: ScoringContext = { hour: 12, isDark: false };
export const NIGHT: ScoringContext = { hour: 23, isDark: true };
