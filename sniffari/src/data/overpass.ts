import type { LatLon, OverpassResponse } from '../types';

/** [south, west, north, east] in degrees — Overpass bbox order. */
export type BBox = [number, number, number, number];

export interface Tile {
  key: string;
  bbox: BBox;
}

/** ~2.2 km × 1.7 km at 41°N. A 1.5 mi radius walk touches ~9–12 tiles. */
export const TILE_DEG = 0.02;

/** Bump when the query changes so cached tiles are refetched. */
export const QUERY_VERSION = 1;

export const OVERPASS_ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

export function bboxAround(center: LatLon, radiusM: number): BBox {
  const dLat = radiusM / 110_574;
  const dLon = radiusM / (111_320 * Math.cos((center.lat * Math.PI) / 180));
  return [center.lat - dLat, center.lon - dLon, center.lat + dLat, center.lon + dLon];
}

/** Fixed global grid so tiles cache and dedupe across sessions and start points. */
export function tilesForBBox([s, w, n, e]: BBox): Tile[] {
  const tiles: Tile[] = [];
  const i0 = Math.floor(s / TILE_DEG);
  const i1 = Math.floor(n / TILE_DEG);
  const j0 = Math.floor(w / TILE_DEG);
  const j1 = Math.floor(e / TILE_DEG);
  for (let i = i0; i <= i1; i++) {
    for (let j = j0; j <= j1; j++) {
      const r = (v: number) => Math.round(v * 1e6) / 1e6;
      tiles.push({ key: `${i}_${j}`, bbox: [r(i * TILE_DEG), r(j * TILE_DEG), r((i + 1) * TILE_DEG), r((j + 1) * TILE_DEG)] });
    }
  }
  return tiles;
}

const HIGHWAYS =
  'motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|' +
  'unclassified|road|residential|living_street|service|pedestrian|footway|path|bridleway|cycleway|track|steps|construction';

/**
 * One query per tile, three output blocks:
 *  1. walkable ways (body) + all their nodes (body, so crossing/signal tags come along)
 *  2. context areas & lines with inline geometry: grass, parks, woods, tree rows, rail, major roads
 *     already covered by (1) — plus multipolygon relations
 *  3. point features: trees, shops/food, transit, amenities; shops mapped as buildings via `out center`
 */
export function buildQuery(bbox: BBox, timeoutS = 90): string {
  // Explicit per-statement bbox (not the global [bbox:] setting) so that
  // node(w.roads) returns every node of a road, even beyond the tile edge.
  const b = `(${bbox.join(',')})`;
  return `[out:json][timeout:${timeoutS}];
way["highway"~"^(${HIGHWAYS})$"]${b}->.roads;
.roads out body qt;
node(w.roads);
out body qt;
(
  way["landuse"~"^(grass|meadow|village_green|recreation_ground|forest)$"]${b};
  way["leisure"~"^(park|garden|dog_park|common)$"]${b};
  way["natural"~"^(grassland|scrub|heath|wood|tree_row)$"]${b};
  way["railway"~"^(rail|light_rail|subway)$"]${b};
)->.areas;
.areas out geom qt;
(
  relation["type"="multipolygon"]["landuse"~"^(grass|meadow|village_green|recreation_ground|forest)$"]${b};
  relation["type"="multipolygon"]["leisure"~"^(park|garden|dog_park|common)$"]${b};
  relation["type"="multipolygon"]["natural"~"^(grassland|scrub|heath|wood)$"]${b};
)->.rels;
.rels out geom qt;
(
  node["natural"="tree"]${b};
  node["shop"]${b};
  node["amenity"~"^(restaurant|bar|cafe|fast_food|pub|food_court|ice_cream|nightclub|biergarten|waste_basket|waste_disposal|dog_toilet|drinking_water|water_point|bench|vending_machine)$"]${b};
  node["leisure"~"^(dog_park|picnic_table)$"]${b};
  node["highway"="bus_stop"]${b};
  node["public_transport"~"^(station|platform)$"]${b};
  node["railway"="station"]${b};
  node["dog"="yes"]${b};
)->.pois;
.pois out body qt;
(
  way["shop"]${b};
  way["amenity"~"^(restaurant|bar|cafe|fast_food|pub|food_court|ice_cream|nightclub|biergarten)$"]${b};
  way["railway"="station"]${b};
  way["public_transport"="station"]${b};
  way["leisure"="dog_park"]${b};
)->.poiAreas;
.poiAreas out tags center qt;`;
}

export class OverpassError extends Error {
  constructor(message: string, readonly status?: number) {
    super(message);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * POST a query, trying each endpoint in turn. 429/504 (rate limit / busy)
 * back off and retry once per endpoint before moving on.
 */
export async function fetchOverpass(
  query: string,
  opts: { signal?: AbortSignal; endpoints?: string[]; fetchImpl?: typeof fetch } = {},
): Promise<OverpassResponse> {
  const endpoints = opts.endpoints ?? OVERPASS_ENDPOINTS;
  const f = opts.fetchImpl ?? fetch;
  let lastErr: unknown;
  for (const url of endpoints) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const res = await f(url, {
          method: 'POST',
          body: new URLSearchParams({ data: query }),
          signal: opts.signal,
        });
        if (res.status === 429 || res.status === 504) {
          lastErr = new OverpassError(`Overpass busy (${res.status})`, res.status);
          await sleep(2000 * (attempt + 1));
          continue;
        }
        if (!res.ok) throw new OverpassError(`Overpass error ${res.status}`, res.status);
        const json = (await res.json()) as OverpassResponse & { remark?: string };
        if (json.remark && /runtime error|timed out/i.test(json.remark)) {
          throw new OverpassError(`Overpass: ${json.remark}`);
        }
        return json;
      } catch (e) {
        if ((e as Error).name === 'AbortError') throw e;
        lastErr = e;
        break;
      }
    }
  }
  throw lastErr instanceof Error ? lastErr : new OverpassError('Overpass unavailable');
}
