import { describe, expect, it } from 'vitest';
import synthetic from '../../fixtures/synthetic.overpass.json';
import meta from '../../fixtures/synthetic.meta.json';
import type { OverpassResponse } from '../types';
import { buildScoredGraphInputs, scoreAll } from './pipeline';
import { PROFILES } from '../scoring/profiles';
import { NOON } from '../test/helpers';
import { astar, makeRoutingGraph } from './astar';
import { Planner, trimSpurs, type Bounds } from './loopGenerator';
import { makeProjection } from '../graph/geo';
import { overlap } from '../scoring/scoreRoute';

const g = buildScoredGraphInputs([synthetic as unknown as OverpassResponse], meta.center, meta.radiusM);
const scores = scoreAll(g.edges, PROFILES.everyday, NOON);
const proj = makeProjection(meta.center);
const at = (x: number, y: number) => proj.toLatLon(x, y);
const nodeAt = (x: number, y: number) => g.nodes.find((n) => Math.hypot(n.x - x, n.y - y) < 1)!.id;
const planner = new Planner(g, scores, PROFILES.everyday, NOON);
const base = { paceMph: 2.2, tolerance: 0.1, bounds: null, end: null };

describe('astar', () => {
  const rg = makeRoutingGraph(g, scores);
  it('finds a connected path and never uses excluded edges', () => {
    const r = astar(rg, nodeAt(-300, -200), nodeAt(0, 200))!;
    expect(r.steps.length).toBeGreaterThan(0);
    for (const s of r.steps) expect(scores[s.edgeId]!.excluded).toBeNull();
    // steps chain end-to-end
    let n = nodeAt(-300, -200);
    for (const s of r.steps) {
      const e = g.edges[s.edgeId]!;
      expect(s.forward ? e.from : e.to).toBe(n);
      n = s.forward ? e.to : e.from;
    }
    expect(n).toBe(nodeAt(0, 200));
  });
  it('detours off busy Main St when a quiet parallel exists', () => {
    const r = astar(rg, nodeAt(-300, 0), nodeAt(0, 0))!;
    const onMain = r.steps.filter((s) => g.edges[s.edgeId]!.name === 'Main Street').length;
    expect(onMain).toBe(0);
  });
  it('trimSpurs removes immediate back-and-forth', () => {
    expect(trimSpurs([{ edgeId: 1, forward: true }, { edgeId: 2, forward: true }, { edgeId: 2, forward: false }, { edgeId: 3, forward: true }])).toEqual([
      { edgeId: 1, forward: true },
      { edgeId: 3, forward: true },
    ]);
  });
});

describe('loop planner', () => {
  const start = at(0, 200); // Cottage Pl × Oak Ave
  const res = planner.plan({ ...base, start, targetM: 1400 });

  it('returns up to 3 distinct loops that start and end at the walker', () => {
    expect(res.routes.length).toBeGreaterThanOrEqual(2);
    expect(res.routes.length).toBeLessThanOrEqual(3);
    for (const r of res.routes) {
      const [a, z] = [r.coords[0]!, r.coords[r.coords.length - 1]!];
      expect(a).toEqual(z);
      expect(r.score).toBeGreaterThanOrEqual(0);
      expect(r.score).toBeLessThanOrEqual(100);
      expect(r.why.length).toBeGreaterThan(10);
      expect(r.durationMin).toBeCloseTo(r.lengthM / 1609.344 / 2.2 * 60);
    }
    for (let i = 0; i < res.routes.length; i++)
      for (let j = i + 1; j < res.routes.length; j++) expect(overlap(res.routes[i]!, res.routes[j]!, g)).toBeLessThan(0.4);
  });
  it('ranks best first and keeps the best loop off busy Main St', () => {
    const scoresDesc = res.routes.map((r) => r.score);
    expect([...scoresDesc].sort((a, b) => b - a)).toEqual(scoresDesc);
    const best = res.routes[0]!;
    const mainM = best.edgeIds.filter((id) => g.edges[id]!.name === 'Main Street').reduce((s, id) => s + g.edges[id]!.lengthM, 0);
    expect(mainM / best.lengthM).toBeLessThan(0.15);
  });
  it('stays inside the map view it was given', () => {
    const b: Bounds = [at(0, 50).lat, at(-320, 0).lon, at(0, 420).lat, at(20, 0).lon];
    const inView = planner.plan({ ...base, start, targetM: 1000, bounds: b });
    expect(inView.routes.length).toBeGreaterThan(0);
    const pad = 0.0016;
    for (const r of inView.routes)
      for (const [lon, lat] of r.coords) {
        expect(lat).toBeGreaterThanOrEqual(b[0] - pad);
        expect(lat).toBeLessThanOrEqual(b[2] + pad);
        expect(lon).toBeGreaterThanOrEqual(b[1] - pad);
        expect(lon).toBeLessThanOrEqual(b[3] + pad);
      }
  });
});

describe('one-way planner', () => {
  it('routes to a chosen end point with alternatives', () => {
    const res = planner.plan({ ...base, start: at(0, -200), end: at(-300, 300), targetM: 0 });
    expect(res.routes.length).toBeGreaterThan(0);
    const last = res.routes[0]!.coords[res.routes[0]!.coords.length - 1]!;
    const [x, y] = proj.toXY(last[1], last[0]);
    expect(Math.hypot(x + 300, y - 300)).toBeLessThan(5);
  });
  it('explains when nothing is reachable', () => {
    const far = planner.plan({ ...base, start: at(5000, 5000), targetM: 1000 });
    expect(far.routes).toEqual([]);
    expect(far.message).toMatch(/No walkable street/);
  });
});

describe('crossing detection', () => {
  it('walking along a busy road is not crossing it; going across is', () => {
    const rg = makeRoutingGraph(g, scores);
    // Straight up Broadway (tertiary) from Elm to Oak: many Broadway intersections, zero crossings.
    const along = astar(rg, nodeAt(-300, -200), nodeAt(-300, 200))!;
    const alongRoute = planner['build'](along.steps, 't', { ...base, start: at(0, 0), targetM: 0 }, null);
    const onBroadway = along.steps.every((s) => g.edges[s.edgeId]!.name === 'Broadway');
    if (onBroadway) expect(alongRoute.crossings).toEqual([]);
    // Cottage Pl straight across Main St (signals) counts one signalised crossing.
    const across = astar(rg, nodeAt(0, -200), nodeAt(0, 200))!;
    const r = planner['build'](across.steps, 't2', { ...base, start: at(0, 0), targetM: 0 }, null);
    expect(r.crossings.filter((k) => k === 'signals').length).toBeGreaterThanOrEqual(1);
  });
});
