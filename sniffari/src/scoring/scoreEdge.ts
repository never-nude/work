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

/**
 * Busy streets must never score well just because they have sidewalks and
 * lights. The quiet subscore acts as a multiplier on the weighted mean:
 * no penalty at quiet ≥ 0.7, falling steeply below it.
 *   residential 1.0 → ×1   tertiary 0.6 → ×0.89   secondary 0.3 → ×0.53   primary 0.1 → ×0.23
 */
export const VETO_THRESHOLD = 0.7;
export const VETO_EXPONENT = 0.75;

export function trafficVeto(quietScore: number): number {
  return Math.min(1, quietScore / VETO_THRESHOLD) ** VETO_EXPONENT;
}

/** Edge quality q = weighted mean of factor subscores (SPEC §6) × traffic veto. All factors are evaluated for explainability. */
export function scoreEdge(
  f: EdgeFeatures,
  weights: Partial<Record<EdgeFactorKey, number>>,
  ctx: ScoringContext,
): EdgeScore {
  const factors: EdgeScore['factors'] = {};
  for (const k of Object.keys(EDGE_FACTORS) as EdgeFactorKey[]) factors[k] = EDGE_FACTORS[k](f, ctx);
  const bonus = amenities(f, ctx);
  const excluded = exclusionReason(f);
  const veto = trafficVeto(factors.quiet!.score);
  if (excluded) return { q: 0, excluded, factors, amenities: bonus, veto };
  let mean = 0;
  for (const k of Object.keys(weights) as EdgeFactorKey[]) mean += weights[k]! * factors[k]!.score;
  return { q: mean * veto, excluded: null, factors, amenities: bonus, veto };
}

/** Routing cost = length × (1 + α(1 − q)). Excluded edges are impassable. */
export function edgeCost(lengthM: number, s: EdgeScore, alpha = DEFAULT_ALPHA): number {
  if (s.excluded) return Infinity;
  return lengthM * (1 + alpha * (1 - s.q));
}
