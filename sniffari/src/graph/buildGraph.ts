import type {
  CrossingKind,
  Edge,
  GraphNode,
  LatLon,
  LngLat,
  OsmTags,
  OverpassNode,
  OverpassRelation,
  OverpassResponse,
  OverpassWay,
} from '../types';
import { makeProjection, polylineLengthXY, type Projection } from './geo';
import { isCrossingRoad, isGraphWay, roadClassOf } from './osmTags';

/** Merged, de-duplicated OSM elements from one or more (tile) responses. */
export interface OsmData {
  nodes: Map<number, OverpassNode>;
  ways: Map<number, OverpassWay>;
  relations: Map<number, OverpassRelation>;
}

export function mergeResponses(responses: OverpassResponse[]): OsmData {
  const nodes = new Map<number, OverpassNode>();
  const ways = new Map<number, OverpassWay>();
  const relations = new Map<number, OverpassRelation>();
  // The same element can arrive from several tiles or query blocks with different
  // detail (skel vs body vs geom). Merge instead of overwrite.
  for (const r of responses) {
    for (const el of r.elements) {
      if (el.type === 'node') {
        const prev = nodes.get(el.id);
        nodes.set(el.id, prev ? { ...prev, ...el, tags: { ...prev.tags, ...el.tags } } : el);
      } else if (el.type === 'way') {
        const prev = ways.get(el.id);
        ways.set(
          el.id,
          prev
            ? {
                ...prev,
                ...el,
                nodes: el.nodes ?? prev.nodes,
                geometry: el.geometry ?? prev.geometry,
                tags: { ...prev.tags, ...el.tags },
              }
            : el,
        );
      } else {
        const prev = relations.get(el.id);
        relations.set(el.id, prev ? { ...prev, ...el, members: el.members ?? prev.members } : el);
      }
    }
  }
  return { nodes, ways, relations };
}

/** Resolve a way's polyline, from inline geometry or referenced nodes. */
export function wayCoords(way: OverpassWay, nodes: Map<number, OverpassNode>): LatLon[] {
  if (way.geometry && way.geometry.length > 0) return way.geometry;
  if (!way.nodes) return [];
  const out: LatLon[] = [];
  for (const id of way.nodes) {
    const n = nodes.get(id);
    if (n) out.push({ lat: n.lat, lon: n.lon });
  }
  return out;
}

export type EdgeBase = Omit<Edge, 'features'>;

export interface BaseGraph {
  nodes: GraphNode[];
  edges: EdgeBase[];
  center: LatLon;
  projection: Projection;
}

export interface BuildOptions {
  /** Drop edges whose midpoint is farther than this from the center. */
  radiusM?: number;
}

/**
 * Turn highway ways into a routable graph: split every way at nodes shared
 * with another way (intersections) and at its ends. Excluded ways (motorways,
 * private roads…) are kept as edges so the debug layer can show them —
 * the scorer marks them as excluded and the router will skip them.
 */
export function buildGraph(osm: OsmData, center: LatLon, opts: BuildOptions = {}): BaseGraph {
  const projection = makeProjection(center);
  const graphWays: OverpassWay[] = [];
  for (const w of osm.ways.values()) {
    if (w.nodes && w.nodes.length >= 2 && isGraphWay(w.tags)) graphWays.push(w);
  }

  // Count way-node references to find intersections.
  const refCount = new Map<number, number>();
  for (const w of graphWays) {
    const seen = new Set<number>();
    for (const id of w.nodes!) {
      // A way that revisits a node (closed loop) makes it a junction too.
      refCount.set(id, (refCount.get(id) ?? 0) + (seen.has(id) ? 2 : 1));
      seen.add(id);
    }
  }

  const nodeIndex = new Map<number, number>(); // osm id → dense id
  const nodes: GraphNode[] = [];
  const edges: EdgeBase[] = [];
  const maxR = opts.radiusM ?? Infinity;

  const ensureNode = (osmId: number): number => {
    let id = nodeIndex.get(osmId);
    if (id !== undefined) return id;
    const n = osm.nodes.get(osmId)!;
    const [x, y] = projection.toXY(n.lat, n.lon);
    id = nodes.length;
    nodes.push({ id, osmId, lat: n.lat, lon: n.lon, x, y, tags: n.tags, crossing: 'none', edgeIds: [] });
    nodeIndex.set(osmId, id);
    return id;
  };

  // A way whose nodes weren't all fetched (edge of the loaded area) is split
  // into runs of known nodes rather than bridged with a straight line.
  const runs: { way: OverpassWay; ids: number[] }[] = [];
  for (const w of graphWays) {
    let run: number[] = [];
    for (const id of w.nodes!) {
      if (osm.nodes.has(id)) run.push(id);
      else {
        if (run.length >= 2) runs.push({ way: w, ids: run });
        run = [];
      }
    }
    if (run.length >= 2) runs.push({ way: w, ids: run });
  }

  for (const { way: w, ids } of runs) {
    let start = 0;
    for (let i = 1; i < ids.length; i++) {
      const isLast = i === ids.length - 1;
      if (!isLast && (refCount.get(ids[i]!) ?? 0) < 2) continue;
      const slice = ids.slice(start, i + 1);
      start = i;
      if (slice[0] === slice[slice.length - 1] && slice.length < 3) continue;

      const coords: LngLat[] = slice.map((id) => {
        const n = osm.nodes.get(id)!;
        return [n.lon, n.lat];
      });
      const xy = coords.map(([lon, lat]) => projection.toXY(lat, lon));
      const lengthM = polylineLengthXY(xy);
      if (lengthM < 0.5) continue;

      if (maxR !== Infinity) {
        const mid = xy[xy.length >> 1]!;
        const a = xy[0]!;
        const b = xy[xy.length - 1]!;
        const inside = [a, mid, b].some((p) => Math.hypot(p[0], p[1]) <= maxR);
        if (!inside) continue;
      }

      const from = ensureNode(slice[0]!);
      const to = ensureNode(slice[slice.length - 1]!);
      const tags: OsmTags = w.tags ?? {};
      const edge: EdgeBase = {
        id: edges.length,
        wayId: w.id,
        from,
        to,
        coords,
        lengthM,
        name: tags.name ?? tags.ref ?? null,
        tags,
      };
      edges.push(edge);
      nodes[from]!.edgeIds.push(edge.id);
      if (to !== from) nodes[to]!.edgeIds.push(edge.id);
    }
  }

  classifyCrossings(nodes, edges);
  return { nodes, edges, center, projection };
}

function nodeCrossingFromTags(tags: OsmTags | undefined): CrossingKind | null {
  if (!tags) return null;
  if (tags.railway === 'level_crossing' || tags.railway === 'crossing') return 'rail';
  const c = tags.crossing;
  if (tags.highway === 'traffic_signals' || c === 'traffic_signals' || tags['crossing:signals'] === 'yes') {
    return 'signals';
  }
  if (c === 'marked' || c === 'zebra' || c === 'uncontrolled' || tags.crossing_ref === 'zebra') return 'marked';
  if (c === 'unmarked' || c === 'no') return 'unmarked';
  if (tags.highway === 'crossing') return 'unknown';
  return null;
}

/**
 * Tag crossings of busy (tertiary+) roads. A node on a busy road where a
 * walkable non-major way joins is a crossing; its kind comes from the node's
 * own tags, else from traffic signals within 25 m (signals are often tagged
 * on a neighbouring node), else "unmarked".
 */
function classifyCrossings(nodes: GraphNode[], edges: EdgeBase[]): void {
  const signalNodes = nodes.filter((n) => nodeCrossingFromTags(n.tags) === 'signals');
  for (const n of nodes) {
    const tagged = nodeCrossingFromTags(n.tags);
    if (tagged === 'rail') {
      n.crossing = 'rail';
      continue;
    }
    let onMajor = false;
    let joinsOther = false;
    const ways = new Set<number>();
    for (const eid of n.edgeIds) {
      const e = edges[eid]!;
      ways.add(e.wayId);
      if (isCrossingRoad(roadClassOf(e.tags.highway ?? ''))) onMajor = true;
      else joinsOther = true;
    }
    if (!onMajor || (!joinsOther && ways.size < 2)) continue;
    if (tagged) {
      n.crossing = tagged;
      continue;
    }
    const nearSignals = signalNodes.some((s) => Math.hypot(s.x - n.x, s.y - n.y) <= 25);
    n.crossing = nearSignals ? 'signals' : 'unmarked';
  }
}
