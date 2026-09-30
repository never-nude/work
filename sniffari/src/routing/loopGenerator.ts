import type { EdgeScore, Graph, LatLon, Profile, Route, ScoringContext } from '../types';
import { haversineM, makeProjection } from '../graph/geo';
import { PointIndex } from '../graph/spatialIndex';
import { overlap, scoreRoute } from '../scoring/scoreRoute';
import { astar, makeRoutingGraph, type RoutingGraph, type Step } from './astar';

/** [south, west, north, east] degrees. */
export type Bounds = [number, number, number, number];

export interface PlanRequest {
  start: LatLon;
  /** null = loop back to start. */
  end: LatLon | null;
  /** Target length for loops (metres). One-way routes ignore it. */
  targetM: number;
  paceMph: number;
  tolerance: number;
  /** Only route on streets inside these bounds (the user's map view). */
  bounds: Bounds | null;
}

export interface PlanResult {
  routes: Route[];
  candidates: number;
  message?: string;
}

const MAX_ROUTES = 3;
const MAX_OVERLAP = 0.4;
/** Cost multiplier on edges used by earlier legs, to discourage doubling back. */
const REUSE_MULTIPLIER = 4;
/** Street distance ≈ 1.3 × straight-line distance in typical grids. */
const CIRCUITY = 1.3;

function inBounds(p: LatLon, b: Bounds): boolean {
  return p.lat >= b[0] && p.lat <= b[2] && p.lon >= b[1] && p.lon <= b[3];
}

/**
 * The area routes may use: the view grown to include start (and finish), then
 * padded by 20% of its size (at least ~250 m) so paths between points near the
 * edge — or a start just off-screen — still have streets to use.
 */
export function planningBounds(view: Bounds, pts: LatLon[]): Bounds {
  let [s, w, n, e] = view;
  for (const p of pts) {
    s = Math.min(s, p.lat);
    n = Math.max(n, p.lat);
    w = Math.min(w, p.lon);
    e = Math.max(e, p.lon);
  }
  const padLat = Math.max((n - s) * 0.2, 0.00225);
  const padLon = Math.max((e - w) * 0.2, 0.003);
  return [s - padLat, w - padLon, n + padLat, e + padLon];
}

export class Planner {
  private readonly nodeIndex: PointIndex<number>;

  constructor(
    private readonly graph: Graph,
    private readonly scores: EdgeScore[],
    private readonly profile: Profile,
    private readonly ctx: ScoringContext,
  ) {
    this.nodeIndex = new PointIndex(graph.nodes.map((n) => ({ x: n.x, y: n.y, item: n.id })));
  }

  plan(req: PlanRequest, onProgress?: (done: number, total: number) => void): PlanResult {
    let bounds = req.bounds;
    if (bounds) bounds = planningBounds(bounds, req.end ? [req.start, req.end] : [req.start]);
    const b = bounds;
    const allowEdge = b
      ? (id: number) => {
          const e = this.graph.edges[id]!;
          const a = this.graph.nodes[e.from]!, z = this.graph.nodes[e.to]!;
          return inBounds(a, b) && inBounds(z, b);
        }
      : undefined;
    const rg = makeRoutingGraph(this.graph, this.scores, { allowEdge, crossingWeight: this.profile.weights.crossings ?? 0 });

    const startNode = this.snap(rg, req.start);
    if (startNode === null) return { routes: [], candidates: 0, message: 'No walkable street near your starting point in this view.' };

    if (req.end) return this.oneWay(rg, startNode, req);
    return this.loops(rg, startNode, req, b, onProgress);
  }

  /** Nearest node with at least one routable edge. */
  private snap(rg: RoutingGraph, p: LatLon, exclude?: number): number | null {
    const proj = makeProjection(this.graph.center);
    const [x, y] = proj.toXY(p.lat, p.lon);
    for (const r of [60, 150, 400]) {
      const ids = this.nodeIndex
        .within(x, y, r)
        .filter((id) => id !== exclude && this.graph.nodes[id]!.edgeIds.some((e) => rg.cost[e] !== Infinity))
        .sort((a, c) => {
          const na = this.graph.nodes[a]!, nc = this.graph.nodes[c]!;
          return Math.hypot(na.x - x, na.y - y) - Math.hypot(nc.x - x, nc.y - y);
        });
      if (ids.length) return ids[0]!;
    }
    return null;
  }

  private build(steps: Step[], id: string, req: PlanRequest, targetM: number | null): Route {
    return scoreRoute(
      { graph: this.graph, scores: this.scores, profile: this.profile, ctx: this.ctx, steps, targetM, tolerance: req.tolerance, paceMph: req.paceMph },
      id,
    );
  }

  private pickDistinct(candidates: Route[]): Route[] {
    const sorted = [...candidates].sort((a, b) => b.score - a.score);
    const out: Route[] = [];
    for (const r of sorted) {
      if (out.every((o) => overlap(r, o, this.graph) < MAX_OVERLAP)) out.push(r);
      if (out.length === MAX_ROUTES) break;
    }
    return out;
  }

  /** Best path to a chosen end point, plus alternatives found by penalising the previous best. */
  private oneWay(rg: RoutingGraph, startNode: number, req: PlanRequest): PlanResult {
    if (haversineM(req.start, req.end!) < 40) {
      return { routes: [], candidates: 0, message: "That finish is right where you're starting — pick a spot further away, or choose Back to start." };
    }
    // Never snap the finish onto the start corner (a zero-length "route").
    const endNode = this.snap(rg, req.end!, startNode);
    if (endNode === null) return { routes: [], candidates: 0, message: 'No walkable street near that end point in this view.' };
    const mult = new Map<number, number>();
    const cands: Route[] = [];
    for (let i = 0; i < 6; i++) {
      const r = astar(rg, startNode, endNode, mult);
      if (!r || r.steps.length === 0) break;
      cands.push(this.build(r.steps, `oneway-${i}`, req, null));
      for (const s of r.steps) mult.set(s.edgeId, (mult.get(s.edgeId) ?? 1) * 1.6);
    }
    if (!cands.length) return { routes: [], candidates: 0, message: "Couldn't find a walkable path to that point inside this view." };
    return { routes: this.pickDistinct(cands), candidates: cands.length };
  }

  /**
   * SPEC §7.3: candidate loops through two waypoints at varied bearings and
   * radii (a triangle start → W1 → W2 → start), each leg routed with A*,
   * later legs penalised for reusing earlier edges.
   */
  private loops(rg: RoutingGraph, startNode: number, req: PlanRequest, bounds: Bounds | null, onProgress?: (d: number, t: number) => void): PlanResult {
    const s = this.graph.nodes[startNode]!;
    const proj = makeProjection(this.graph.center);
    const baseR = req.targetM / (3 * CIRCUITY);
    const bearings = 16;
    const scales = [0.7, 1, 1.3];
    const total = bearings * scales.length;
    const cands: Route[] = [];
    const seenShapes = new Set<string>();
    let done = 0;

    for (const k of scales) {
      for (let i = 0; i < bearings; i++) {
        onProgress?.(done++, total);
        const th = (i / bearings) * 2 * Math.PI;
        const R = baseR * k;
        const wps: number[] = [];
        for (const a of [th, th + Math.PI / 3]) {
          let wx = s.x + R * Math.cos(a), wy = s.y + R * Math.sin(a);
          // Pull waypoints that fall outside the view back toward the start.
          if (bounds) {
            for (let t = 0; t < 6 && !inBounds(proj.toLatLon(wx, wy), bounds); t++) {
              wx = s.x + (wx - s.x) * 0.75;
              wy = s.y + (wy - s.y) * 0.75;
            }
          }
          const n = this.snap(rg, proj.toLatLon(wx, wy));
          if (n !== null && n !== startNode) wps.push(n);
        }
        if (wps.length < 2 || wps[0] === wps[1]) continue;
        const key = wps.join('-');
        if (seenShapes.has(key)) continue;
        seenShapes.add(key);

        const legs = [startNode, wps[0]!, wps[1]!, startNode];
        const mult = new Map<number, number>();
        const steps: Step[] = [];
        let ok = true;
        for (let l = 0; l < 3; l++) {
          const r = astar(rg, legs[l]!, legs[l + 1]!, mult);
          if (!r) {
            ok = false;
            break;
          }
          for (const st of r.steps) mult.set(st.edgeId, REUSE_MULTIPLIER);
          steps.push(...r.steps);
        }
        if (!ok || steps.length < 3) continue;
        cands.push(this.build(trimSpurs(steps), `loop-${cands.length}`, req, req.targetM));
      }
    }
    onProgress?.(total, total);
    if (!cands.length) return { routes: [], candidates: 0, message: 'No loop fits in this view — zoom out a little or pick a shorter walk.' };

    // Prefer loops within tolerance; fall back to the closest fits if none are.
    const fits = cands.filter((r) => Math.abs(r.lengthM - req.targetM) / req.targetM <= req.tolerance * 1.5);
    const pool = fits.length >= MAX_ROUTES ? fits : cands;
    return { routes: this.pickDistinct(pool), candidates: cands.length };
  }
}

/** Remove immediate out-and-back spurs (…A→B, B→A…) that leg joins can create. */
export function trimSpurs(steps: Step[]): Step[] {
  const out: Step[] = [];
  for (const st of steps) {
    const prev = out[out.length - 1];
    if (prev && prev.edgeId === st.edgeId && prev.forward !== st.forward) out.pop();
    else out.push(st);
  }
  return out;
}

export function makePlanner(graph: Graph, scores: EdgeScore[], profile: Profile, ctx: ScoringContext): Planner {
  return new Planner(graph, scores, profile, ctx);
}
