import type { EdgeFactorKey, EdgeFeatures, EdgeScore, FactorKey, Profile, ScoringContext } from '../types';
import { amenities, EDGE_FACTORS, exclusionReason } from './factors';

/** α in SPEC §6: a q=0 edge costs (1+α)× its length. */
export const DEFAULT_ALPHA = 3;

/**
 * The per-edge weights actually in play for this profile and moment:
 * route-level factors dropped, lighting only after dark, then normalised.
 */
export function effectiveEdgeWeights(
  profile: Profile,
  ctx: ScoringContext,
  overrides?: Partial<Record<FactorKey, number>>,
): Partial<Record<EdgeFactorKey, number>> {
  const w = { ...profile.weights, ...overrides };
  const out: Partial<Record<EdgeFactorKey, number>> = {};
  let sum = 0;
  for (const k of Object.keys(EDGE_FACTORS) as EdgeFactorKey[]) {
    if (k === 'lighting' && !ctx.isDark) continue;
    const v = w[k] ?? 0;
    if (v <= 0) continue;
    out[k] = v;
    sum += v;
  }
  if (sum > 0) for (const k of Object.keys(out) as EdgeFactorKey[]) out[k]! /= sum;
  return out;
}

/** Edge quality q = weighted mean of factor subscores (SPEC §6). All factors are evaluated for explainability. */
export function scoreEdge(
  f: EdgeFeatures,
  weights: Partial<Record<EdgeFactorKey, number>>,
  ctx: ScoringContext,
): EdgeScore {
  const factors: EdgeScore['factors'] = {};
  for (const k of Object.keys(EDGE_FACTORS) as EdgeFactorKey[]) factors[k] = EDGE_FACTORS[k](f, ctx);
  const bonus = amenities(f, ctx);
  const excluded = exclusionReason(f);
  if (excluded) return { q: 0, excluded, factors, amenities: bonus };
  let q = 0;
  for (const k of Object.keys(weights) as EdgeFactorKey[]) q += weights[k]! * factors[k]!.score;
  return { q, excluded: null, factors, amenities: bonus };
}

/** Routing cost = length × (1 + α(1 − q)). Excluded edges are impassable. */
export function edgeCost(lengthM: number, s: EdgeScore, alpha = DEFAULT_ALPHA): number {
  if (s.excluded) return Infinity;
  return lengthM * (1 + alpha * (1 - s.q));
}
