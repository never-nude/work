import { describe, expect, it } from 'vitest';
import type { LngLat } from '../types';
import { makePositionGate, mayPublishPosition, publicRoute } from './privacy';

// ~1.1 km straight line north, points every ~11 m
const line: LngLat[] = Array.from({ length: 101 }, (_, i) => [-73.76, 41.03 + i * 0.0001]);
// loop: out and back to the same point
const loop: LngLat[] = [...line, ...[...line].reverse().slice(1)];

describe('privacy', () => {
  it('trims ~150 m off both ends of the shared route', () => {
    const r = publicRoute(line);
    expect(r[0]![1]).toBeGreaterThan(41.03 + 0.00135);
    expect(r.at(-1)![1]).toBeLessThan(41.03 + 0.01 - 0.00135);
  });
  it('a loop starting at home never shares the home end', () => {
    for (const [, lat] of publicRoute(loop)) expect(Math.abs(lat - 41.03)).toBeGreaterThan(0.00135);
  });
  it('holds the live position until the walker is away from start and finish', () => {
    expect(mayPublishPosition({ lat: 41.0301, lon: -73.76 }, loop)).toBe(false);
    expect(mayPublishPosition({ lat: 41.035, lon: -73.76 }, loop)).toBe(true);
  });
  it('rate-limits position uploads', () => {
    const gate = makePositionGate(15_000, 20);
    expect(gate({ lat: 41.03, lon: -73.76 }, 0)).toBe(true);
    expect(gate({ lat: 41.031, lon: -73.76 }, 5_000)).toBe(false); // too soon
    expect(gate({ lat: 41.03001, lon: -73.76 }, 20_000)).toBe(false); // hasn't moved
    expect(gate({ lat: 41.031, lon: -73.76 }, 20_000)).toBe(true);
  });
});
