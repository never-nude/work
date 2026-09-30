import type { EdgeFeatures } from '../../types';
import { isMajorRoad } from '../../graph/osmTags';

/** Longest stretch of a separately-sidewalked busy road kept as a crossing connector. */
export const SEPARATE_CONNECTOR_M = 30;

const FOOT_OK = new Set(['yes', 'designated', 'permissive', 'official']);

/**
 * Factors 10 & 11 (rules + hazards) as hard exclusions. Returns the reason an
 * edge must never be routed, or null. Excluded edges get q = 0.
 */
export function exclusionReason(f: EdgeFeatures): string | null {
  if (f.roadClass === 'motorway' || f.roadClass === 'trunk') return 'Highway — no walking';
  if (f.construction) return 'Under construction';
  if (f.dog === 'no') return 'No dogs allowed';
  if (f.foot === 'no' || f.foot === 'use_sidepath') return 'No pedestrians';
  if ((f.access === 'private' || f.access === 'no') && !FOOT_OK.has(f.foot ?? '')) return 'Private — no access';
  if (f.service === 'driveway' || f.service === 'drive-through') return 'Driveway';
  if (isMajorRoad(f.roadClass) && f.sidewalk === 'none') return 'Busy road with no sidewalk';
  // Sidewalks exist as their own footways — walk those, not the roadway. Short
  // pieces stay routable so the graph keeps its crossings at intersections.
  if (isMajorRoad(f.roadClass) && f.sidewalk === 'separate' && f.lengthM > SEPARATE_CONNECTOR_M) {
    return 'Sidewalks mapped separately — walk those';
  }
  return null;
}
