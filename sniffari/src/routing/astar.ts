import type { CrossingKind, EdgeScore, Graph } from '../types';
import { CROSSING_PENALTY } from '../scoring/factors/crossings';
import { edgeCost } from '../scoring/scoreEdge';
import { isCrossingRoad } from '../graph/osmTags';

/** One traversed edge; `forward` = walked from edge.from to edge.to. */
export interface Step {
  edgeId: number;
  forward: boolean;
}

/**
 * Routing view of a scored graph: per-edge costs (SPEC §6) plus per-node
 * crossing penalties, restricted to an allowed set of edges (e.g. the map view).
 */
export interface RoutingGraph {
  graph: Graph;
  cost: Float64Array; // Infinity = not routable
  nodePenalty: Float64Array; // metres-equivalent added when crossing at a node
  /** 1 for edges that are themselves busy roads — walking along one isn't crossing it. */
  busy: Uint8Array;
}

/** A busy crossing costs like walking this many extra metres of a q=0 street, scaled by the kind's penalty. */
export const CROSSING_COST_M = 150;

export function makeRoutingGraph(
  graph: Graph,
  scores: EdgeScore[],
  opts: { allowEdge?: (edgeId: number) => boolean; crossingWeight?: number } = {},
): RoutingGraph {
  const cost = new Float64Array(graph.edges.length);
  const busy = new Uint8Array(graph.edges.length);
  for (const e of graph.edges) {
    busy[e.id] = isBusyEdge(e.features.roadClass) ? 1 : 0;
    const allowed = opts.allowEdge ? opts.allowEdge(e.id) : true;
    cost[e.id] = allowed ? edgeCost(e.lengthM, scores[e.id]!) : Infinity;
  }
  // Profile's crossings weight relative to the SPEC's typical 0.15.
  const scale = (opts.crossingWeight ?? 0.15) / 0.15;
  const nodePenalty = new Float64Array(graph.nodes.length);
  for (const n of graph.nodes) {
    if (n.crossing !== 'none') nodePenalty[n.id] = CROSSING_PENALTY[n.crossing as Exclude<CrossingKind, 'none'>] * CROSSING_COST_M * scale;
  }
  return { graph, cost, nodePenalty, busy };
}

class MinHeap {
  private ids: number[] = [];
  private keys: number[] = [];
  get size() {
    return this.ids.length;
  }
  push(id: number, key: number) {
    const ids = this.ids, keys = this.keys;
    let i = ids.length;
    ids.push(id);
    keys.push(key);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (keys[p]! <= key) break;
      ids[i] = ids[p]!;
      keys[i] = keys[p]!;
      i = p;
    }
    ids[i] = id;
    keys[i] = key;
  }
  pop(): number {
    const ids = this.ids, keys = this.keys;
    const top = ids[0]!;
    const lastId = ids.pop()!;
    const lastKey = keys.pop()!;
    if (ids.length) {
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        if (l >= ids.length) break;
        const r = l + 1;
        const c = r < ids.length && keys[r]! < keys[l]! ? r : l;
        if (keys[c]! >= lastKey) break;
        ids[i] = ids[c]!;
        keys[i] = keys[c]!;
        i = c;
      }
      ids[i] = lastId;
      keys[i] = lastKey;
    }
    return top;
  }
}

/**
 * A* over the routing graph. `multiplier` inflates edges already used by
 * earlier legs of the same loop so it doesn't double back.
 * Heuristic = straight-line metres, admissible because cost ≥ length.
 */
export function astar(
  rg: RoutingGraph,
  from: number,
  to: number,
  multiplier?: Map<number, number>,
): { steps: Step[]; cost: number } | null {
  if (from === to) return { steps: [], cost: 0 };
  const { graph, cost, nodePenalty, busy } = rg;
  const nodes = graph.nodes;
  const target = nodes[to]!;
  const g = new Float64Array(nodes.length).fill(Infinity);
  const via = new Int32Array(nodes.length).fill(-1);
  const closed = new Uint8Array(nodes.length);
  const heap = new MinHeap();
  const h = (n: number) => Math.hypot(nodes[n]!.x - target.x, nodes[n]!.y - target.y);
  g[from] = 0;
  heap.push(from, h(from));
  while (heap.size) {
    const u = heap.pop();
    if (closed[u]) continue;
    if (u === to) break;
    closed[u] = 1;
    for (const eid of nodes[u]!.edgeIds) {
      let c = cost[eid]!;
      if (c === Infinity) continue;
      const m = multiplier?.get(eid);
      if (m) c *= m;
      const e = graph.edges[eid]!;
      const v = e.from === u ? e.to : e.from;
      if (closed[v]) continue;
      // Arriving at a busy-road node from a side street means crossing it (approximation:
      // we don't know the exit edge yet; walking along the busy road itself is never penalised).
      const nv = g[u]! + c + (v === to || busy[eid] ? 0 : nodePenalty[v]!);
      if (nv < g[v]!) {
        g[v] = nv;
        via[v] = eid;
        heap.push(v, nv + h(v));
      }
    }
  }
  if (g[to] === Infinity) return null;
  const steps: Step[] = [];
  let n = to;
  while (n !== from) {
    const eid = via[n]!;
    const e = graph.edges[eid]!;
    const prev = e.from === n ? e.to : e.from;
    steps.push({ edgeId: eid, forward: e.to === n });
    n = prev;
  }
  steps.reverse();
  return { steps, cost: g[to]! };
}

function isBusyEdge(rc: import('../types').RoadClass): boolean {
  return isCrossingRoad(rc);
}

/** A crossing happens at a busy-road node only when the walker goes across it: neither the arriving nor leaving edge is the busy road. */
export function crossesAt(graph: Graph, inEdge: number, outEdge: number): boolean {
  const a = graph.edges[inEdge]!.features.roadClass;
  const b = graph.edges[outEdge]!.features.roadClass;
  return !isCrossingRoad(a) && !isCrossingRoad(b);
}
