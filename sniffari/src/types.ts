// Core domain types for Sniffari. See docs/PLAN.md for how they fit together.

export interface LatLon {
  lat: number;
  lon: number;
}

/** [lon, lat] — GeoJSON / MapLibre order. */
export type LngLat = [number, number];

export type OsmTags = Record<string, string>;

// ---------------------------------------------------------------- OSM input

export interface OverpassNode {
  type: 'node';
  id: number;
  lat: number;
  lon: number;
  tags?: OsmTags;
}

export interface OverpassWay {
  type: 'way';
  id: number;
  nodes?: number[];
  /** Present when queried with `out geom`. */
  geometry?: LatLon[];
  /** Present when queried with `out center`. */
  center?: LatLon;
  tags?: OsmTags;
}

export interface OverpassRelationMember {
  type: 'node' | 'way' | 'relation';
  ref: number;
  role: string;
  geometry?: LatLon[];
}

export interface OverpassRelation {
  type: 'relation';
  id: number;
  members?: OverpassRelationMember[];
  center?: LatLon;
  tags?: OsmTags;
}

export type OverpassElement = OverpassNode | OverpassWay | OverpassRelation;

export interface OverpassResponse {
  elements: OverpassElement[];
}

// ---------------------------------------------------------------- graph

export type RoadClass =
  | 'motorway'
  | 'trunk'
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'unclassified'
  | 'residential'
  | 'living_street'
  | 'service'
  | 'pedestrian'
  | 'footway'
  | 'path'
  | 'cycleway'
  | 'track'
  | 'steps'
  | 'construction'
  | 'other';

/** How a walker gets across the road at a node. `none` = not a crossing of a major road. */
export type CrossingKind = 'signals' | 'marked' | 'unmarked' | 'unknown' | 'rail' | 'none';

export interface GraphNode {
  /** Dense index into Graph.nodes. */
  id: number;
  osmId: number;
  lat: number;
  lon: number;
  /** Local planar metres (see graph/geo.ts). */
  x: number;
  y: number;
  tags?: OsmTags;
  crossing: CrossingKind;
  edgeIds: number[];
}

export type SidewalkState =
  | 'dedicated' // the way itself is a footway / sidewalk / pedestrian street
  | 'both'
  | 'one'
  | 'separate' // road tagged sidewalk=separate — sidewalk exists as its own way
  | 'none'
  | 'unknown';

export type SurfaceKind = 'paved' | 'unpaved' | 'unknown';
export type LitState = 'yes' | 'no' | 'unknown';

export interface AmenityCounts {
  wasteBaskets: number;
  bagDispensers: number;
  water: number;
  dogWater: number;
  benches: number;
  dogFriendly: number;
}

/**
 * Everything a factor needs to know about an edge, precomputed once per graph.
 * Factors read only this (plus ScoringContext) — never raw OSM.
 */
export interface EdgeFeatures {
  highway: string;
  roadClass: RoadClass;
  footwayType: string | null; // footway=sidewalk / crossing / …
  service: string | null;
  sidewalk: SidewalkState;
  maxspeedMph: number | null;
  lanes: number | null;
  foot: string | null;
  access: string | null;
  dog: string | null;
  construction: boolean;
  surface: SurfaceKind;
  lit: LitState;

  lengthM: number;
  /**
   * Terrain from the elevation model: mean absolute grade (%) along the edge,
   * and metres climbed per 100 m. null when elevation is unavailable.
   */
  gradePct: number | null;
  climbPer100m: number | null;

  /** Median distance (m) of edge samples to the nearest other major road (secondary+). */
  distMajorRoadM: number;
  /** Median distance (m) to the nearest railway line. */
  distRailM: number;
  /** Fraction of samples inside or within ~15 m of mapped grass/park/green. */
  grassFraction: number;
  /** Distance (m) from the edge's closest sample to the nearest grass area. */
  nearGrassM: number;
  /** Fraction of samples inside or within ~20 m of a dog park (kept apart from grass: opt-in preference). */
  dogParkFraction: number;
  /** Distance (m) to the nearest dog park. */
  nearDogParkM: number;
  /** Mapped trees within 15 m, per 100 m of edge. */
  treesPer100m: number;
  /** Fraction of samples inside or within ~10 m of wood/forest/tree rows. */
  canopyFraction: number;
  /** Shops + food/drink POIs within 50 m, per 100 m of edge. */
  commercialPer100m: number;
  /** Distance (m) to nearest rail/transit station. */
  distStationM: number;
  busStops: number;
  amenities: AmenityCounts;
}

export interface Edge {
  id: number;
  wayId: number;
  from: number;
  to: number;
  /** [lon, lat] polyline. */
  coords: LngLat[];
  lengthM: number;
  name: string | null;
  tags: OsmTags;
  features: EdgeFeatures;
}

export interface Graph {
  nodes: GraphNode[];
  edges: Edge[];
  center: LatLon;
}

// ---------------------------------------------------------------- scoring

export type EdgeFactorKey =
  | 'sidewalk'
  | 'quiet'
  | 'grass'
  | 'shade'
  | 'crowds'
  | 'surface'
  | 'lighting'
  | 'terrain';

/** Route-level factors live alongside edge factors in a profile. */
export type FactorKey = EdgeFactorKey | 'crossings';

export interface FactorResult {
  /** Subscore in [0, 1]; 1 is best. */
  score: number;
  /** Short human-readable explanation, e.g. "Sidewalks both sides". */
  reason: string;
}

export interface WeatherContext {
  tempF: number;
  uvIndex: number;
  precipLast24hMm: number;
  snowLast48hCm: number;
}

export interface ScoringContext {
  /** Local hour 0–23 of the planned departure. */
  hour: number;
  isDark: boolean;
  /** Count dog parks as sniffable green. Off by default: dog parks are neutral. */
  dogParks?: boolean;
  /** Phase 4. Absent means "no weather adjustments". */
  weather?: WeatherContext;
}

export type EdgeFactor = (edge: EdgeFeatures, ctx: ScoringContext) => FactorResult;

export interface Profile {
  id: ProfileId;
  name: string;
  blurb: string;
  /** Relative weights; normalised at scoring time over the factors in play. */
  weights: Partial<Record<FactorKey, number>>;
  /** Scales the additive amenity bonus (route-level). */
  amenityBonus: number;
  /** Potty break: prefer the shortest walk that reaches good grass. */
  shortWalk?: boolean;
}

export type ProfileId = 'everyday' | 'quiet' | 'sniffy' | 'potty' | 'senior';

export interface EdgeScore {
  /** Quality in [0,1]. 0 for excluded edges. */
  q: number;
  /** Exclusion reason, or null if routable. */
  excluded: string | null;
  factors: Partial<Record<EdgeFactorKey, FactorResult>>;
  /** Amenity subscore in [0,1] — a bonus, not part of q. */
  amenities: FactorResult;
  /** Traffic multiplier applied to the weighted mean (1 = no penalty). */
  veto: number;
}

// ---------------------------------------------------------------- routing (Phase 2+)

export type WalkMode = 'loop' | 'out-and-back' | 'one-way';

export interface WalkRequest {
  start: LatLon;
  mode: WalkMode;
  /** Resolved target distance in metres (duration × pace, or given directly). */
  targetM: number;
  paceMph: number;
  /** Fractional tolerance, default 0.1. */
  tolerance: number;
  departure: Date;
  profileId: ProfileId;
  /** Slider overrides on top of the profile. */
  weightOverrides?: Partial<Record<FactorKey, number>>;
  destinationId?: string;
}

export interface PointOfInterest {
  kind: 'grass' | 'water' | 'waste' | 'bench' | 'dog-friendly' | 'dog-park';
  lat: number;
  lon: number;
  name?: string;
}

export interface RouteWarning {
  kind: 'hot-pavement' | 'busy-crossing' | 'unlit' | 'no-sidewalk' | 'salt' | 'steep';
  message: string;
  at?: LatLon;
}

export interface Route {
  id: string;
  edgeIds: number[];
  coords: LngLat[];
  lengthM: number;
  durationMin: number;
  /** 0–100. */
  score: number;
  breakdown: Partial<Record<FactorKey, number>>;
  why: string;
  pois: PointOfInterest[];
  warnings: RouteWarning[];
  /** Fraction of the length walked twice (loops should rarely double back). */
  retraceFraction: number;
  crossings: CrossingKind[];
}

export type DestinationKind = 'dog-park' | 'park' | 'grass' | 'patio' | 'pet-store';

export interface Destination {
  id: string;
  kind: DestinationKind;
  name: string | null;
  lat: number;
  lon: number;
  /** Graph node the router targets. */
  nodeId: number;
  /** Intrinsic quality in [0,1] (size, dog rules, amenities). */
  quality: number;
}
