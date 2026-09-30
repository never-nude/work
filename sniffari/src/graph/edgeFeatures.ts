import type { AmenityCounts, Edge, EdgeFeatures, LatLon, OsmTags } from '../types';
import type { BaseGraph, EdgeBase, OsmData } from './buildGraph';
import { wayCoords } from './buildGraph';
import { median, samplePolyline, type Projection } from './geo';
import type { ElevationAt } from '../data/elevation';
import { describeUnnamedEdges } from './edgeNames';
import {
  isMajorRoad,
  parseLanes,
  parseLit,
  parseMaxspeedMph,
  parseSidewalk,
  parseSurface,
  roadClassOf,
} from './osmTags';
import { AreaIndex, PointIndex, SegmentIndex } from './spatialIndex';

type AmenityKind = keyof AmenityCounts;

/** Spatial layers built once per graph, queried per edge sample. */
export interface FeatureLayers {
  majorRoads: SegmentIndex;
  rail: SegmentIndex;
  grass: AreaIndex;
  canopy: AreaIndex;
  dogParks: AreaIndex;
  trees: PointIndex<number>;
  commercial: PointIndex<number>;
  stations: PointIndex<number>;
  busStops: PointIndex<number>;
  amenities: PointIndex<AmenityKind>;
}

const SAMPLE_SPACING_M = 10;
const CAP_M = 1000; // "far away" — keeps numbers finite for display and JSON

const FOOD = new Set(['restaurant', 'bar', 'cafe', 'fast_food', 'pub', 'food_court', 'ice_cream', 'nightclub', 'biergarten']);

function isGrass(t: OsmTags): boolean {
  if (t.access === 'private' || t.access === 'no') return false;
  return (
    ['grass', 'meadow', 'village_green', 'recreation_ground'].includes(t.landuse ?? '') ||
    // Dog parks are deliberately neutral (not counted as sniffable green) — Mike, 2026-09-29.
    ['park', 'garden', 'common'].includes(t.leisure ?? '') ||
    ['grassland', 'scrub', 'heath'].includes(t.natural ?? '')
  );
}

function isCanopy(t: OsmTags): boolean {
  return t.landuse === 'forest' || t.natural === 'wood' || t.natural === 'tree_row';
}

function isRail(t: OsmTags): boolean {
  return ['rail', 'light_rail', 'subway'].includes(t.railway ?? '') && t.tunnel !== 'yes';
}

function isCommercial(t: OsmTags): boolean {
  return (t.shop !== undefined && t.shop !== 'vacant') || FOOD.has(t.amenity ?? '');
}

function isStation(t: OsmTags): boolean {
  return t.railway === 'station' || (t.public_transport === 'station' && t.bus !== 'yes');
}

function isBusStop(t: OsmTags): boolean {
  return t.highway === 'bus_stop' || (t.public_transport === 'platform' && t.bus === 'yes');
}

function amenityKind(t: OsmTags): AmenityKind | null {
  if (t.amenity === 'waste_basket' || t.amenity === 'waste_disposal') return 'wasteBaskets';
  if (t.vending === 'excrement_bags' || t.amenity === 'dog_toilet') return 'bagDispensers';
  if (t.amenity === 'drinking_water' || t.amenity === 'water_point') return t.dog === 'yes' ? 'dogWater' : 'water';
  if (t.amenity === 'bench' || t.leisure === 'picnic_table') return 'benches';
  if (t.dog === 'yes' && (t.shop !== undefined || t.amenity !== undefined)) return 'dogFriendly';
  if (t.shop === 'pet' || t.shop === 'pet_grooming') return 'dogFriendly';
  return null;
}

function isClosed(pts: LatLon[]): boolean {
  if (pts.length < 4) return false;
  const a = pts[0]!;
  const b = pts[pts.length - 1]!;
  return a.lat === b.lat && a.lon === b.lon;
}

export function buildFeatureLayers(osm: OsmData, proj: Projection): FeatureLayers {
  const majorRoads = new SegmentIndex();
  const rail = new SegmentIndex();
  const grass = new AreaIndex();
  const canopy = new AreaIndex();
  const dogParks = new AreaIndex();
  const trees: { x: number; y: number; item: number }[] = [];
  const commercial: { x: number; y: number; item: number }[] = [];
  const stations: { x: number; y: number; item: number }[] = [];
  const busStops: { x: number; y: number; item: number }[] = [];
  const amenities: { x: number; y: number; item: AmenityKind }[] = [];

  const xy = (pts: LatLon[]) => pts.map((p) => proj.toXY(p.lat, p.lon));

  const addPoint = (id: number, t: OsmTags, p: LatLon) => {
    const [x, y] = proj.toXY(p.lat, p.lon);
    if (t.natural === 'tree') trees.push({ x, y, item: id });
    if (isCommercial(t)) commercial.push({ x, y, item: id });
    if (isStation(t)) stations.push({ x, y, item: id });
    if (isBusStop(t)) busStops.push({ x, y, item: id });
    const ak = amenityKind(t);
    if (ak) amenities.push({ x, y, item: ak });
  };

  for (const n of osm.nodes.values()) {
    if (n.tags) addPoint(n.id, n.tags, n);
  }

  for (const w of osm.ways.values()) {
    const t = w.tags;
    if (!t) continue;
    const hw = t.highway;
    const needsGeom = (hw && isMajorRoad(roadClassOf(hw))) || isRail(t) || isGrass(t) || isCanopy(t) || t.leisure === 'dog_park';
    if (needsGeom) {
      const coords = wayCoords(w, osm.nodes);
      if (coords.length >= 2) {
        const pts = xy(coords);
        if (hw && isMajorRoad(roadClassOf(hw)) && t.tunnel !== 'yes') majorRoads.addLine(pts, w.id);
        if (isRail(t)) rail.addLine(pts, w.id);
        if (isGrass(t)) grass.add(pts, isClosed(coords));
        if (isCanopy(t)) canopy.add(pts, isClosed(coords) && t.natural !== 'tree_row');
        if (t.leisure === 'dog_park') dogParks.add(pts, isClosed(coords));
      }
    }
    // Shops, cafés, stations mapped as buildings/areas arrive with `out center`.
    if (w.center && !hw) addPoint(w.id, t, w.center);
  }

  for (const r of osm.relations.values()) {
    const t = r.tags;
    if (!t) continue;
    const grassy = isGrass(t);
    const woody = isCanopy(t);
    if (grassy || woody) {
      for (const m of r.members ?? []) {
        if (m.type !== 'way' || m.role === 'inner' || !m.geometry || m.geometry.length < 2) continue;
        const pts = xy(m.geometry);
        // Member ways of a multipolygon are often open fragments of one ring.
        // Fragments still give a usable boundary distance; closed members add containment.
        if (grassy) grass.add(pts, isClosed(m.geometry));
        if (woody) canopy.add(pts, isClosed(m.geometry));
      }
    }
    if (r.center) addPoint(r.id, t, r.center);
  }

  return {
    majorRoads: majorRoads.finish(),
    rail: rail.finish(),
    grass: grass.finish(),
    canopy: canopy.finish(),
    dogParks: dogParks.finish(),
    trees: new PointIndex(trees),
    commercial: new PointIndex(commercial),
    stations: new PointIndex(stations),
    busStops: new PointIndex(busStops),
    amenities: new PointIndex(amenities),
  };
}

function uniqueWithin<T>(index: PointIndex<T>, samples: [number, number][], r: number): Set<number> {
  const out = new Set<number>();
  for (const [x, y] of samples) for (const i of index.withinIdx(x, y, r)) out.add(i);
  return out;
}

const TERRAIN_SPACING_M = 20;

/**
 * Mean absolute grade and climb along an edge, sampled every 20 m (the DEM is
 * ~7–10 m/pixel; finer sampling mostly measures noise). Bridges and tunnels
 * are skipped — the DEM sees the ground under them, not the deck.
 */
export function terrainOf(
  edge: EdgeBase,
  xy: [number, number][],
  proj: Projection,
  elevationAt?: ElevationAt,
): { gradePct: number | null; climbPer100m: number | null } {
  const none = { gradePct: null, climbPer100m: null };
  if (!elevationAt || edge.tags.bridge === 'yes' || edge.tags.tunnel === 'yes' || edge.lengthM < 5) return none;
  const pts = samplePolyline(xy, TERRAIN_SPACING_M);
  const h: number[] = [];
  for (const [x, y] of pts) {
    const v = elevationAt(proj.toLatLon(x, y));
    if (v === null || !Number.isFinite(v)) return none;
    h.push(v);
  }
  let abs = 0;
  let climb = 0;
  for (let i = 1; i < h.length; i++) {
    const d = h[i]! - h[i - 1]!;
    abs += Math.abs(d);
    if (d > 0) climb += d;
  }
  // Direction-neutral climb: a walk may go either way along the edge.
  const up = Math.max(climb, abs - climb);
  return { gradePct: (abs / edge.lengthM) * 100, climbPer100m: (up / edge.lengthM) * 100 };
}

export function computeEdgeFeatures(
  edge: EdgeBase,
  layers: FeatureLayers,
  proj: Projection,
  elevationAt?: ElevationAt,
): EdgeFeatures {
  const t = edge.tags;
  const highway = t.highway ?? '';
  const rc = roadClassOf(highway);
  const xy = edge.coords.map(([lon, lat]) => proj.toXY(lat, lon));
  const samples = samplePolyline(xy, SAMPLE_SPACING_M);
  const per100 = Math.max(edge.lengthM, 20) / 100;

  const cap = (d: number) => Math.min(CAP_M, d);
  const notSelf = (owner: number) => owner === edge.wayId;

  const distMajorRoadM = cap(median(samples.map(([x, y]) => layers.majorRoads.nearestDist(x, y, 300, notSelf))));
  const distRailM = cap(median(samples.map(([x, y]) => layers.rail.nearestDist(x, y, 500))));

  let grassHits = 0;
  let nearGrassM = Infinity;
  let canopyHits = 0;
  let dogParkHits = 0;
  let nearDogParkM = Infinity;
  for (const [x, y] of samples) {
    const g = layers.grass.distance(x, y, 400);
    if (g <= 20) grassHits++;
    if (g < nearGrassM) nearGrassM = g;
    if (layers.canopy.distance(x, y, 10) <= 10) canopyHits++;
    const dp = layers.dogParks.distance(x, y, 400);
    if (dp <= 20) dogParkHits++;
    if (dp < nearDogParkM) nearDogParkM = dp;
  }

  const trees = uniqueWithin(layers.trees, samples, 15).size;
  const commercial = uniqueWithin(layers.commercial, samples, 50).size;
  const busStops = uniqueWithin(layers.busStops, samples, 30).size;
  const distStationM = cap(Math.min(...samples.map(([x, y]) => layers.stations.nearestDist(x, y, 800))));

  const amenities: AmenityCounts = { wasteBaskets: 0, bagDispensers: 0, water: 0, dogWater: 0, benches: 0, dogFriendly: 0 };
  for (const i of uniqueWithin(layers.amenities, samples, 25)) amenities[layers.amenities.item(i)]++;

  return {
    highway,
    roadClass: rc,
    footwayType: t.footway ?? null,
    service: t.service ?? null,
    sidewalk: parseSidewalk(t, rc),
    maxspeedMph: parseMaxspeedMph(t.maxspeed),
    lanes: parseLanes(t.lanes),
    foot: t.foot ?? null,
    access: t.access ?? null,
    dog: t.dog ?? null,
    construction: rc === 'construction' || t.construction !== undefined,
    lengthM: edge.lengthM,
    ...terrainOf(edge, xy, proj, elevationAt),
    surface: parseSurface(t, rc),
    lit: parseLit(t.lit),
    distMajorRoadM,
    distRailM,
    grassFraction: samples.length ? grassHits / samples.length : 0,
    nearGrassM: cap(nearGrassM),
    dogParkFraction: samples.length ? dogParkHits / samples.length : 0,
    nearDogParkM: cap(nearDogParkM),
    treesPer100m: trees / per100,
    canopyFraction: samples.length ? canopyHits / samples.length : 0,
    commercialPer100m: commercial / per100,
    distStationM,
    busStops,
    amenities,
  };
}

export function attachFeatures(
  base: BaseGraph,
  osm: OsmData,
  onProgress?: (done: number, total: number) => void,
  elevationAt?: ElevationAt,
): Edge[] {
  const layers = buildFeatureLayers(osm, base.projection);
  const out: Edge[] = [];
  const total = base.edges.length;
  for (let i = 0; i < total; i++) {
    const e = base.edges[i]!;
    out.push({ ...e, features: computeEdgeFeatures(e, layers, base.projection, elevationAt) });
    if (onProgress && i % 500 === 0) onProgress(i, total);
  }
  onProgress?.(total, total);
  for (const [id, label] of describeUnnamedEdges(out, osm, base.projection)) out[id]!.name = label;
  return out;
}
