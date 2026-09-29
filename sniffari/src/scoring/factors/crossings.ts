import type { CrossingKind, FactorResult } from '../../types';
import { clamp01 } from './util';

/** Penalty per crossing of a secondary+ road (or railway), by crossing type. */
export const CROSSING_PENALTY: Record<Exclude<CrossingKind, 'none'>, number> = {
  signals: 0.15,
  marked: 0.35,
  unknown: 0.5,
  unmarked: 0.8,
  rail: 0.4,
};

const LABEL: Record<Exclude<CrossingKind, 'none'>, string> = {
  signals: 'signalised',
  marked: 'marked',
  unknown: 'crosswalk',
  unmarked: 'unmarked',
  rail: 'rail',
};

/**
 * Factor 5 — route-level. Scores the major-road crossings a route makes,
 * normalised by route length so a 3 km loop with two signalised crossings
 * isn't treated like a 300 m walk with the same two.
 */
export function crossingsFactor(kinds: CrossingKind[], routeLengthM: number): FactorResult {
  const counted = kinds.filter((k): k is Exclude<CrossingKind, 'none'> => k !== 'none');
  if (counted.length === 0) return { score: 1, reason: 'No busy-road crossings' };
  const penalty = counted.reduce((sum, k) => sum + CROSSING_PENALTY[k], 0);
  const km = Math.max(0.5, routeLengthM / 1000);
  const score = clamp01(1 / (1 + penalty / km));
  const tally = new Map<string, number>();
  for (const k of counted) tally.set(LABEL[k], (tally.get(LABEL[k]) ?? 0) + 1);
  const parts = [...tally].map(([label, n]) => `${n} ${label}`);
  return { score, reason: `${parts.join(', ')} crossing${counted.length === 1 ? '' : 's'} of busy roads` };
}
