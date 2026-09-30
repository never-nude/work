import type { Edge, LatLon } from '../types';
import type { OsmData } from './buildGraph';
import { wayCoords } from './buildGraph';
import { pointInRing, type Projection } from './geo';
import { SegmentIndex } from './spatialIndex';

interface NamedArea {
  name: string;
  ring: [number, number][];
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

const PLACE_KEYS = ['leisure', 'landuse', 'amenity', 'natural', 'tourism'];

/**
 * OSM rarely names footways, so "Unnamed footway" was most of the map.
 * Describe them from their surroundings instead:
 *   sidewalk  → "Sidewalk · Main Street"      (nearest named street)
 *   crossing  → "Crosswalk · Hamilton Avenue" (the street it crosses)
 *   in a park → "Path in Cottage Green"
 *   otherwise → "Path near Oak Avenue", or a plain type label
 * Real OSM names always win. Returns the new name per edge id.
 */
export function describeUnnamedEdges(edges: Edge[], osm: OsmData, proj: Projection): Map<number, string> {
  const streets = new SegmentIndex();
  const streetName = new Map<number, string>();
  const areas: NamedArea[] = [];

  const toXY = (pts: LatLon[]) => pts.map((p) => proj.toXY(p.lat, p.lon));

  for (const w of osm.ways.values()) {
    const t = w.tags;
    if (!t?.name) continue;
    if (t.highway && !['footway', 'path', 'steps', 'cycleway', 'bridleway', 'corridor'].includes(t.highway)) {
      const pts = toXY(wayCoords(w, osm.nodes));
      if (pts.length >= 2) {
        streets.addLine(pts, w.id);
        streetName.set(w.id, t.name);
      }
    } else if (PLACE_KEYS.some((k) => t[k]) && !t.highway) {
      const coords = wayCoords(w, osm.nodes);
      if (coords.length >= 4) addArea(areas, t.name, toXY(coords));
    }
  }
  for (const r of osm.relations.values()) {
    const name = r.tags?.name;
    if (!name || !PLACE_KEYS.some((k) => r.tags![k])) continue;
    for (const m of r.members ?? []) {
      if (m.type === 'way' && m.role !== 'inner' && m.geometry && m.geometry.length >= 4) addArea(areas, name, toXY(m.geometry));
    }
  }
  streets.finish();

  const nearestStreet = (x: number, y: number, maxM: number): string | null => {
    const hit = streets.nearestOwner(x, y, maxM);
    return hit ? (streetName.get(hit.ownerId) ?? null) : null;
  };

  const out = new Map<number, string>();
  for (const e of edges) {
    if (e.tags.name || e.tags.ref) continue;
    const mid = e.coords[e.coords.length >> 1]!;
    const [x, y] = proj.toXY(mid[1], mid[0]);
    const f = e.features;
    const hw = f.highway;
    let label: string | null = null;

    if (f.footwayType === 'sidewalk') {
      const st = nearestStreet(x, y, 35);
      label = st ? `Sidewalk · ${st}` : 'Sidewalk';
    } else if (f.footwayType === 'crossing' || hw === 'crossing') {
      const st = nearestStreet(x, y, 20);
      label = st ? `Crosswalk · ${st}` : 'Crosswalk';
    } else if (['footway', 'path', 'steps', 'pedestrian', 'track', 'cycleway', 'bridleway'].includes(hw)) {
      const kind = hw === 'steps' ? 'Steps' : hw === 'cycleway' ? 'Bike path' : hw === 'track' ? 'Track' : hw === 'pedestrian' ? 'Plaza' : 'Path';
      const area = areas.find((a) => x >= a.minX && x <= a.maxX && y >= a.minY && y <= a.maxY && pointInRing(x, y, a.ring));
      if (area) label = `${kind} in ${area.name}`;
      else {
        const st = nearestStreet(x, y, 80);
        label = st ? `${kind} near ${st}` : kind;
      }
    } else if (hw === 'service') {
      const kind = f.service === 'parking_aisle' ? 'Parking lot' : f.service === 'alley' ? 'Alley' : 'Service road';
      const st = nearestStreet(x, y, 60);
      label = st ? `${kind} off ${st}` : kind;
    } else {
      const st = nearestStreet(x, y, 40);
      label = st ? `Street near ${st}` : null;
    }
    if (label) out.set(e.id, label);
  }
  return out;
}

function addArea(areas: NamedArea[], name: string, ring: [number, number][]) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const [x, y] of ring) {
    minX = Math.min(minX, x);
    minY = Math.min(minY, y);
    maxX = Math.max(maxX, x);
    maxY = Math.max(maxY, y);
  }
  areas.push({ name, ring, minX, minY, maxX, maxY });
}
