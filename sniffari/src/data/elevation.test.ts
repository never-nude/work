import { describe, expect, it } from 'vitest';
import { decodeRGBA, decodeTerrarium, lonLatToTileXY, makeElevationLookup, tilesForElevation } from './elevation';
import { buildGraph, mergeResponses } from '../graph/buildGraph';
import { attachFeatures } from '../graph/edgeFeatures';
import synthetic from '../../fixtures/synthetic.overpass.json';
import meta from '../../fixtures/synthetic.meta.json';
import type { OverpassResponse } from '../types';

describe('terrarium decoding', () => {
  it('decodes sea level and a hill', () => {
    expect(decodeTerrarium(128, 0, 0)).toBe(0);
    expect(decodeTerrarium(128, 100, 128)).toBe(100.5);
    expect([...decodeRGBA(new Uint8Array([128, 0, 0, 255, 128, 10, 0, 255]))]).toEqual([0, 10]);
  });
  it('maps lat/lon to tiles and covers a bbox', () => {
    const [x, y] = lonLatToTileXY(0, 0, 1);
    expect([x, y]).toEqual([1, 1]);
    expect(tilesForElevation([41.02, -73.78, 41.05, -73.75]).length).toBeGreaterThanOrEqual(4);
  });
  it('bilinearly interpolates within a tile', () => {
    const z = 14;
    const [fx, fy] = lonLatToTileXY(41.0335, -73.763, z);
    const x = Math.floor(fx), y = Math.floor(fy);
    const heights = new Float32Array(256 * 256);
    for (let r = 0; r < 256; r++) for (let c = 0; c < 256; c++) heights[r * 256 + c] = c; // east-rising ramp
    const at = makeElevationLookup([{ z, x, y, heights }]);
    const v = at({ lat: 41.0335, lon: -73.763 })!;
    expect(v).toBeCloseTo((fx - x) * 256 - 0.5, 1);
    expect(at({ lat: 0, lon: 0 })).toBeNull();
  });
});

describe('terrain features', () => {
  const osm = mergeResponses([synthetic as unknown as OverpassResponse]);
  const base = buildGraph(osm, meta.center, { radiusM: meta.radiusM });
  // Synthetic hill: rises 8 m per 100 m going north, flat east–west.
  const slope = ({ lat }: { lat: number }) => (lat - meta.center.lat) * 110_574 * 0.08;
  const edges = attachFeatures(base, osm, undefined, slope);

  it('north–south streets read ~8% grade, east–west ones flat', () => {
    const ns = edges.find((e) => e.name === 'Cottage Place')!;
    const ew = edges.find((e) => e.name === 'Oak Avenue')!;
    expect(ns.features.gradePct).toBeCloseTo(8, 0);
    expect(ns.features.climbPer100m).toBeCloseTo(8, 0);
    expect(ew.features.gradePct).toBeLessThan(0.5);
  });
  it('is null without an elevation source', () => {
    const plain = attachFeatures(base, osm);
    expect(plain.every((e) => e.features.gradePct === null)).toBe(true);
  });
});
