import type { LitState, OsmTags, RoadClass, SidewalkState, SurfaceKind } from '../types';

const ROAD_CLASS: Record<string, RoadClass> = {
  motorway: 'motorway',
  motorway_link: 'motorway',
  trunk: 'trunk',
  trunk_link: 'trunk',
  primary: 'primary',
  primary_link: 'primary',
  secondary: 'secondary',
  secondary_link: 'secondary',
  tertiary: 'tertiary',
  tertiary_link: 'tertiary',
  unclassified: 'unclassified',
  road: 'unclassified',
  residential: 'residential',
  living_street: 'living_street',
  service: 'service',
  pedestrian: 'pedestrian',
  footway: 'footway',
  path: 'path',
  bridleway: 'path',
  cycleway: 'cycleway',
  track: 'track',
  steps: 'steps',
  construction: 'construction',
};

/** highway=* values that never form part of the walk graph, not even as "excluded" edges. */
const NOT_A_WAY = new Set([
  'proposed',
  'abandoned',
  'disused',
  'razed',
  'raceway',
  'bus_guideway',
  'busway',
  'platform',
  'elevator',
  'corridor',
  'escape',
  'emergency_bay',
  'rest_area',
  'services',
]);

export function isGraphWay(tags: OsmTags | undefined): boolean {
  const hw = tags?.highway;
  if (!hw) return false;
  if (NOT_A_WAY.has(hw)) return false;
  if (tags.area === 'yes' && hw !== 'pedestrian' && hw !== 'footway') return false;
  if (tags.indoor === 'yes') return false;
  return true;
}

export function roadClassOf(highway: string): RoadClass {
  return ROAD_CLASS[highway] ?? 'other';
}

const MAJOR: ReadonlySet<RoadClass> = new Set(['motorway', 'trunk', 'primary', 'secondary']);

/** Secondary and above: the roads that make a walk loud and crossings scary. */
export function isMajorRoad(rc: RoadClass): boolean {
  return MAJOR.has(rc);
}

const DEDICATED: ReadonlySet<RoadClass> = new Set(['footway', 'pedestrian', 'path', 'steps', 'living_street']);

function sideValue(v: string | undefined): 'yes' | 'no' | 'separate' | null {
  if (v === undefined) return null;
  if (v === 'separate') return 'separate';
  if (v === 'no' || v === 'none') return 'no';
  return 'yes';
}

export function parseSidewalk(tags: OsmTags, rc: RoadClass): SidewalkState {
  if (DEDICATED.has(rc)) return 'dedicated';
  const s = tags.sidewalk;
  if (s) {
    if (s === 'both' || s === 'yes') return 'both';
    if (s === 'left' || s === 'right') return 'one';
    if (s === 'separate') return 'separate';
    if (s === 'no' || s === 'none') return 'none';
  }
  const both = sideValue(tags['sidewalk:both']);
  if (both === 'yes') return 'both';
  if (both === 'separate') return 'separate';
  if (both === 'no') return 'none';
  const l = sideValue(tags['sidewalk:left']);
  const r = sideValue(tags['sidewalk:right']);
  if (l === null && r === null) return 'unknown';
  const yes = (l === 'yes' ? 1 : 0) + (r === 'yes' ? 1 : 0);
  if (yes === 2) return 'both';
  if (l === 'separate' || r === 'separate') return 'separate';
  if (yes === 1) return 'one';
  if (l === 'no' && r === 'no') return 'none';
  return 'unknown';
}

/** OSM maxspeed → mph. Bare numbers are km/h per OSM convention. */
export function parseMaxspeedMph(v: string | undefined): number | null {
  if (!v) return null;
  const m = /^(\d+(?:\.\d+)?)\s*(mph|km\/h|kmh|kph)?$/i.exec(v.trim());
  if (!m) return null;
  const n = Number(m[1]);
  const unit = m[2]?.toLowerCase();
  return unit === 'mph' ? n : Math.round(n * 0.621371 * 10) / 10;
}

export function parseLanes(v: string | undefined): number | null {
  if (!v) return null;
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : null;
}

const PAVED = new Set([
  'paved', 'asphalt', 'concrete', 'concrete:plates', 'concrete:lanes', 'paving_stones',
  'sett', 'unhewn_cobblestone', 'cobblestone', 'bricks', 'metal', 'wood', 'chipseal',
]);
const UNPAVED = new Set([
  'unpaved', 'gravel', 'fine_gravel', 'dirt', 'earth', 'grass', 'ground', 'mud', 'sand',
  'compacted', 'woodchips', 'pebblestone', 'grass_paver', 'rock',
]);

export function parseSurface(tags: OsmTags, rc: RoadClass): SurfaceKind {
  const s = tags.surface;
  if (s && PAVED.has(s)) return 'paved';
  if (s && UNPAVED.has(s)) return 'unpaved';
  if (!s && rc === 'track') return 'unpaved';
  // Untagged roads in the US are overwhelmingly paved; untagged paths are a coin flip.
  if (!s && !DEDICATED.has(rc) && rc !== 'track' && rc !== 'other') return 'paved';
  return 'unknown';
}

export function parseLit(v: string | undefined): LitState {
  if (!v) return 'unknown';
  if (v === 'no' || v === 'disused') return 'no';
  return 'yes';
}
