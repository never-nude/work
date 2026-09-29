import { describe, expect, it } from 'vitest';
import { haversineM, makeProjection, pointInRing, pointSegmentDist, polylineLengthXY, samplePolyline } from './geo';

describe('geo', () => {
  it('projection round-trips and agrees with haversine', () => {
    const p = makeProjection({ lat: 41.03, lon: -73.76 });
    const [x, y] = p.toXY(41.035, -73.75);
    const back = p.toLatLon(x, y);
    expect(back.lat).toBeCloseTo(41.035, 9);
    expect(back.lon).toBeCloseTo(-73.75, 9);
    const hv = haversineM({ lat: 41.03, lon: -73.76 }, { lat: 41.035, lon: -73.75 });
    expect(Math.hypot(x, y)).toBeCloseTo(hv, -1); // within ~5 m
  });
  it('samples evenly including both ends', () => {
    const s = samplePolyline([[0, 0], [100, 0], [100, 50]], 10);
    expect(s[0]).toEqual([0, 0]);
    expect(s[s.length - 1]).toEqual([100, 50]);
    expect(s.length).toBe(16);
    expect(polylineLengthXY(s)).toBeCloseTo(150);
  });
  it('point-segment and point-in-ring', () => {
    expect(pointSegmentDist(5, 5, 0, 0, 10, 0)).toBe(5);
    expect(pointSegmentDist(-3, 4, 0, 0, 10, 0)).toBe(5);
    const sq: [number, number][] = [[0, 0], [10, 0], [10, 10], [0, 10]];
    expect(pointInRing(5, 5, sq)).toBe(true);
    expect(pointInRing(15, 5, sq)).toBe(false);
  });
});
