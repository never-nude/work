import type {
  CrossingKind,
  EdgeFactorKey,
  EdgeScore,
  FactorKey,
  Graph,
  LngLat,
  Profile,
  Route,
  RouteWarning,
  ScoringContext,
} from '../types';
import { crossesAt, type Step } from '../routing/astar';
import { buildManeuvers } from '../routing/maneuvers';
import { crossingsFactor } from './factors/crossings';
import { effectiveEdgeWeights } from './scoreEdge';

export interface RouteScoreInput {
  graph: Graph;
  scores: EdgeScore[];
  profile: Profile;
  ctx: ScoringContext;
  steps: Step[];
  /** Target length in metres, or null for "just get me there" routes. */
  targetM: number | null;
  tolerance: number;
  paceMph: number;
}

const round = (v: number) => Math.round(v * 100) / 100;

/**
 * Route score 0–100 (SPEC §6): length-weighted mean edge q, blended with the
 * crossings factor at the profile's crossings weight, then adjusted for
 * retracing, distance fit, and an amenity bonus.
 */
export function scoreRoute(input: RouteScoreInput, id: string): Route {
  const { graph, scores, profile, ctx, steps } = input;
  const coords: LngLat[] = [];
  const crossings: CrossingKind[] = [];
  const seen = new Set<number>();
  let lengthM = 0, qSum = 0, retraceM = 0, amenitySum = 0;
  const factorSum: Partial<Record<EdgeFactorKey, number>> = {};
  let noSidewalkM = 0, unlitM = 0, steepM = 0, maxGrade = 0;

  steps.forEach((st, i) => {
    const e = graph.edges[st.edgeId]!;
    const s = scores[st.edgeId]!;
    const pts = st.forward ? e.coords : [...e.coords].reverse();
    coords.push(...(i === 0 ? pts : pts.slice(1)));
    lengthM += e.lengthM;
    qSum += s.q * e.lengthM;
    amenitySum += s.amenities.score;
    if (seen.has(st.edgeId)) retraceM += e.lengthM;
    seen.add(st.edgeId);
    for (const [k, r] of Object.entries(s.factors) as [EdgeFactorKey, { score: number }][]) {
      factorSum[k] = (factorSum[k] ?? 0) + r.score * e.lengthM;
    }
    if ((s.factors.sidewalk?.score ?? 1) <= 0.5) noSidewalkM += e.lengthM;
    if (ctx.isDark && e.features.lit === 'no') unlitM += e.lengthM;
    if ((e.features.gradePct ?? 0) > 8) steepM += e.lengthM;
    maxGrade = Math.max(maxGrade, e.features.gradePct ?? 0);
    // Crossing at the node we arrive at (interior nodes only).
    if (i < steps.length - 1) {
      const node = graph.nodes[st.forward ? e.to : e.from]!;
      if (node.crossing !== 'none' && crossesAt(graph, st.edgeId, steps[i + 1]!.edgeId)) crossings.push(node.crossing);
    }
  });

  const L = Math.max(lengthM, 1);
  const meanQ = qSum / L;
  const cross = crossingsFactor(crossings, lengthM);
  // Crossings' share of the profile, over the factors actually in play right now.
  const inPlay = Object.keys(effectiveEdgeWeights(profile, ctx)) as EdgeFactorKey[];
  const edgeRaw = inPlay.reduce((sum, k) => sum + (profile.weights[k] ?? 0), 0);
  const crossRaw = profile.weights.crossings ?? 0;
  const wc = crossRaw / Math.max(edgeRaw + crossRaw, 1e-9);
  let score = meanQ * (1 - wc) + cross.score * wc;

  const retraceFraction = retraceM / L;
  score *= 1 - 0.5 * retraceFraction;
  if (input.targetM) {
    const dev = Math.abs(lengthM - input.targetM) / input.targetM;
    if (dev > input.tolerance) score *= 1 - Math.min(0.5, (dev - input.tolerance) * 1.5);
  }
  const amenityBonus = Math.min(0.05, (amenitySum / Math.max(1, L / 200)) * 0.02) * profile.amenityBonus;
  score = Math.min(1, score + amenityBonus);

  const breakdown: Partial<Record<FactorKey, number>> = { crossings: round(cross.score) };
  for (const k of Object.keys(factorSum) as EdgeFactorKey[]) breakdown[k] = round(factorSum[k]! / L);

  const warnings: RouteWarning[] = [];
  const busy = crossings.filter((k) => k === 'unmarked' || k === 'unknown').length;
  if (busy) warnings.push({ kind: 'busy-crossing', message: `${busy} busy-road crossing${busy > 1 ? 's' : ''} without signals or markings` });
  if (noSidewalkM > 100) warnings.push({ kind: 'no-sidewalk', message: `${Math.round(noSidewalkM)} m without a mapped sidewalk` });
  if (unlitM > 100) warnings.push({ kind: 'unlit', message: `${Math.round(unlitM)} m unlit after dark` });
  if (steepM > 50) warnings.push({ kind: 'steep', message: `Steep stretch (up to ${Math.round(maxGrade)}% grade)` });

  return {
    id,
    edgeIds: steps.map((s) => s.edgeId),
    coords,
    lengthM,
    durationMin: lengthM / 1609.344 / input.paceMph * 60,
    score: Math.round(score * 100),
    breakdown,
    why: whyLine(breakdown, cross.reason, crossings.length, maxGrade),
    pois: [],
    warnings,
    retraceFraction,
    crossings,
    maneuvers: buildManeuvers(graph, steps, input.targetM !== null),
  };
}

function whyLine(b: Partial<Record<FactorKey, number>>, crossReason: string, nCross: number, maxGrade: number): string {
  const parts: string[] = [];
  const q = b.quiet ?? 0;
  parts.push(q >= 0.85 ? 'Quiet streets almost all the way' : q >= 0.65 ? 'Mostly quiet streets' : 'Some busy stretches');
  const g = b.grass ?? 0;
  if (g >= 0.5) parts.push('green to sniff along the way');
  else if (g >= 0.3) parts.push('some green nearby');
  if ((b.sidewalk ?? 0) >= 0.85) parts.push('sidewalks throughout');
  if (maxGrade > 0) parts.push(maxGrade <= 3 ? 'flat' : maxGrade <= 6 ? 'a few gentle hills' : 'some steep hills');
  parts.push(nCross === 0 ? 'no busy crossings' : crossReason.replace(' of busy roads', ''));
  const text = parts.join(', ');
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Fraction of the shorter route's length shared with the other (SPEC §3: keep < 0.4). */
export function overlap(a: Route, b: Route, graph: Graph): number {
  const setB = new Set(b.edgeIds);
  let shared = 0;
  for (const id of new Set(a.edgeIds)) if (setB.has(id)) shared += graph.edges[id]!.lengthM;
  return shared / Math.max(1, Math.min(a.lengthM, b.lengthM));
}
