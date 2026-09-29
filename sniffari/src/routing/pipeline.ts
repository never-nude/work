import type { Edge, EdgeScore, Graph, LatLon, OverpassResponse, Profile, ScoringContext } from '../types';
import { buildGraph, mergeResponses } from '../graph/buildGraph';
import { attachFeatures } from '../graph/edgeFeatures';
import { effectiveEdgeWeights, scoreEdge } from '../scoring/scoreEdge';
import type { EdgeDetail, HeatmapPayload, HeatmapStats } from './protocol';

export interface BuiltGraph extends Graph {
  msGraph: number;
  msFeatures: number;
}

/** OSM responses → graph with precomputed edge features. The expensive, profile-independent step. */
export function buildScoredGraphInputs(
  responses: OverpassResponse[],
  center: LatLon,
  radiusM: number,
  onProgress?: (stage: 'graph' | 'features', done: number, total: number) => void,
): BuiltGraph {
  const t0 = performance.now();
  const osm = mergeResponses(responses);
  const base = buildGraph(osm, center, { radiusM });
  onProgress?.('graph', 1, 1);
  const t1 = performance.now();
  const edges = attachFeatures(base, osm, (d, t) => onProgress?.('features', d, t));
  const t2 = performance.now();
  return { nodes: base.nodes, edges, center, msGraph: t1 - t0, msFeatures: t2 - t1 };
}

export function scoreAll(edges: Edge[], profile: Profile, ctx: ScoringContext): EdgeScore[] {
  const w = effectiveEdgeWeights(profile, ctx);
  return edges.map((e) => scoreEdge(e.features, w, ctx));
}

export function toHeatmap(
  graph: Graph,
  scores: EdgeScore[],
  timing: Omit<HeatmapStats, 'nodes' | 'edges' | 'excludedEdges' | 'walkableKm' | 'meanQ' | 'crossings'>,
): HeatmapPayload {
  let excluded = 0;
  let walkM = 0;
  let qSum = 0;
  const features: HeatmapPayload['edges']['features'] = graph.edges.map((e, i) => {
    const s = scores[i]!;
    if (s.excluded) excluded++;
    else {
      walkM += e.lengthM;
      qSum += s.q * e.lengthM;
    }
    return {
      type: 'Feature',
      id: e.id,
      geometry: { type: 'LineString', coordinates: e.coords },
      properties: { id: e.id, q: s.excluded ? -1 : Math.round(s.q * 1000) / 1000, name: e.name ?? '' },
    };
  });
  const crossingNodes = graph.nodes.filter((n) => n.crossing !== 'none');
  return {
    edges: { type: 'FeatureCollection', features },
    crossings: {
      type: 'FeatureCollection',
      features: crossingNodes.map((n) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [n.lon, n.lat] },
        properties: { kind: n.crossing },
      })),
    },
    stats: {
      nodes: graph.nodes.length,
      edges: graph.edges.length,
      excludedEdges: excluded,
      walkableKm: walkM / 1000,
      meanQ: walkM > 0 ? qSum / walkM : 0,
      crossings: crossingNodes.length,
      ...timing,
    },
  };
}

export function edgeDetail(graph: Graph, edgeId: number, profile: Profile, ctx: ScoringContext): EdgeDetail | null {
  const e = graph.edges[edgeId];
  if (!e) return null;
  const weights = effectiveEdgeWeights(profile, ctx);
  const mid = e.coords[e.coords.length >> 1]!;
  return {
    id: e.id,
    wayId: e.wayId,
    name: e.name,
    lengthM: e.lengthM,
    tags: e.tags,
    features: e.features,
    score: scoreEdge(e.features, weights, ctx),
    weights,
    mid: { lat: mid[1], lon: mid[0] },
  };
}
