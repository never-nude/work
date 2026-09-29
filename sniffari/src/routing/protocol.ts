import type { EdgeFactorKey, EdgeFeatures, EdgeScore, LatLon, OsmTags, ProfileId, ScoringContext } from '../types';

export type DataSource = { kind: 'live' } | { kind: 'fixture'; name: string };

export type WorkerRequest =
  | {
      type: 'load';
      requestId: number;
      center: LatLon;
      radiusM: number;
      source: DataSource;
      profileId: ProfileId;
      ctx: ScoringContext;
    }
  | { type: 'rescore'; requestId: number; profileId: ProfileId; ctx: ScoringContext }
  | { type: 'inspect'; requestId: number; edgeId: number };

export type Stage = 'fetch' | 'graph' | 'features' | 'score';

export interface HeatmapStats {
  nodes: number;
  edges: number;
  excludedEdges: number;
  walkableKm: number;
  /** Length-weighted mean q over routable edges. */
  meanQ: number;
  crossings: number;
  tiles: { total: number; cached: number };
  ms: { fetch: number; graph: number; features: number; score: number };
}

export interface EdgeProps {
  id: number;
  /** q in [0,1]; -1 for excluded edges (styled separately). */
  q: number;
  name: string;
}

export interface CrossingProps {
  kind: string;
}

export interface HeatmapPayload {
  edges: GeoJSON.FeatureCollection<GeoJSON.LineString, EdgeProps>;
  crossings: GeoJSON.FeatureCollection<GeoJSON.Point, CrossingProps>;
  stats: HeatmapStats;
}

export interface EdgeDetail {
  id: number;
  wayId: number;
  name: string | null;
  lengthM: number;
  tags: OsmTags;
  features: EdgeFeatures;
  score: EdgeScore;
  weights: Partial<Record<EdgeFactorKey, number>>;
  /** Midpoint, for the ground-truth stub. */
  mid: LatLon;
}

export type WorkerResponse =
  | { type: 'progress'; requestId: number; stage: Stage; done: number; total: number; message: string }
  | { type: 'heatmap'; requestId: number; payload: HeatmapPayload }
  | { type: 'detail'; requestId: number; detail: EdgeDetail }
  | { type: 'error'; requestId: number; message: string };
