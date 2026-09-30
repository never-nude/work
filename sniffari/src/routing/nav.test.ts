import { describe, expect, it } from 'vitest';
import synthetic from '../../fixtures/synthetic.overpass.json';
import meta from '../../fixtures/synthetic.meta.json';
import type { OverpassResponse } from '../types';
import { buildScoredGraphInputs, scoreAll } from './pipeline';
import { PROFILES } from '../scoring/profiles';
import { NOON } from '../test/helpers';
import { Planner } from './loopGenerator';
import { makeProjection } from '../graph/geo';
import { kindFor, turnDegrees } from './maneuvers';
import { cumulative, nextManeuver, project } from './progress';

const g = buildScoredGraphInputs([synthetic as unknown as OverpassResponse], meta.center, meta.radiusM);
const planner = new Planner(g, scoreAll(g.edges, PROFILES.everyday, NOON), PROFILES.everyday, NOON);
const proj = makeProjection(meta.center);
const at = (x: number, y: number) => proj.toLatLon(x, y);

describe('turns', () => {
  it('classifies left/right/straight', () => {
    // heading north then east = right turn
    expect(kindFor(turnDegrees([0, 0], [0, 0.001], [0.001, 0.001]))).toBe('right');
    expect(kindFor(turnDegrees([0, 0], [0, 0.001], [-0.001, 0.001]))).toBe('left');
    expect(kindFor(turnDegrees([0, 0], [0, 0.001], [0, 0.002]))).toBe('straight');
  });
});

describe('route maneuvers', () => {
  const r = planner.plan({ start: at(0, 200), end: null, targetM: 1400, paceMph: 2.2, tolerance: 0.1, bounds: null }).routes[0]!;
  it('starts, turns onto named streets, and arrives', () => {
    expect(r.maneuvers[0]!.kind).toBe('start');
    expect(r.maneuvers.at(-1)!.kind).toBe('arrive');
    expect(r.maneuvers.at(-1)!.atM).toBeCloseTo(r.lengthM, 0);
    const turns = r.maneuvers.filter((m) => m.kind !== 'start' && m.kind !== 'arrive');
    expect(turns.length).toBeGreaterThanOrEqual(3); // a loop round blocks turns at least 3 times
    for (const t of turns) expect(t.text).toMatch(/^(Turn|Bear|Sharp|Continue|Turn around)/);
    // ordered along the route
    for (let i = 1; i < r.maneuvers.length; i++) expect(r.maneuvers[i]!.atM).toBeGreaterThanOrEqual(r.maneuvers[i - 1]!.atM);
  });
  it('tracks progress and the next instruction as the walker moves', () => {
    const cum = cumulative(r.coords);
    const mid = r.coords[Math.floor(r.coords.length / 2)]!;
    const p = project(r.coords, cum, { lat: mid[1], lon: mid[0] });
    expect(p.offM).toBeLessThan(1);
    expect(p.alongM).toBeGreaterThan(0);
    const nm = nextManeuver(r.maneuvers, p.alongM)!;
    expect(nm.m.atM).toBeGreaterThanOrEqual(p.alongM - 5);
    // a loop's start and end are the same point: from the start we are at 0, not at the end
    const s = r.coords[0]!;
    expect(project(r.coords, cum, { lat: s[1], lon: s[0] }, 0).alongM).toBeLessThan(5);
    expect(project(r.coords, cum, { lat: s[1], lon: s[0] }, r.lengthM - 20).alongM).toBeGreaterThan(r.lengthM - 30);
  });
  it('reports being off route', () => {
    const cum = cumulative(r.coords);
    const s = r.coords[0]!;
    expect(project(r.coords, cum, { lat: s[1] + 0.002, lon: s[0] + 0.002 }).offM).toBeGreaterThan(100);
  });
});
