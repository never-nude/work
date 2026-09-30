import { describe, expect, it } from 'vitest';
import synthetic from '../../fixtures/synthetic.overpass.json';
import meta from '../../fixtures/synthetic.meta.json';
import type { Edge, OverpassResponse } from '../types';
import { buildGraph, mergeResponses } from './buildGraph';
import { attachFeatures } from './edgeFeatures';
import { effectiveEdgeWeights, scoreEdge } from '../scoring/scoreEdge';
import { PROFILES } from '../scoring/profiles';
import { NOON } from '../test/helpers';
import { makeProjection } from './geo';

const data = synthetic as unknown as OverpassResponse;
const osm = mergeResponses([data]);
const base = buildGraph(osm, meta.center, { radiusM: meta.radiusM });
const edges = attachFeatures(base, osm);

const byName = (name: string) => edges.filter((e) => e.name === name);
const one = (name: string, pred: (e: Edge) => boolean = () => true) => {
  const e = byName(name).find(pred);
  if (!e) throw new Error(`no edge ${name}`);
  return e;
};
const proj = makeProjection(meta.center);
/** Midpoint of an edge in the fixture's local metres (see scripts/make-synthetic-fixture.mjs). */
const mid = (e: Edge) => {
  const [a, b] = [e.coords[0]!, e.coords[e.coords.length - 1]!];
  const [x0, y0] = proj.toXY(a[1], a[0]);
  const [x1, y1] = proj.toXY(b[1], b[0]);
  return { x: (x0 + x1) / 2, y: (y0 + y1) / 2 };
};
const q = (e: Edge) => scoreEdge(e.features, effectiveEdgeWeights(PROFILES.everyday, NOON), NOON);

describe('buildGraph (synthetic fixture)', () => {
  it('splits ways at intersections', () => {
    // Oak Ave: nodes at x = -400,-300,-150,0,150,300; intersections only at -300 and 0 → 3 edges
    expect(byName('Oak Avenue')).toHaveLength(3);
    // Main St sidewalk joins Broadway and Cottage Pl at its two ends only
    expect(byName('Sidewalk · Main Street')).toHaveLength(1);
  });
  it('computes lengths in metres', () => {
    const e = one('Oak Avenue', (e) => mid(e).x < -300);
    expect(e.lengthM).toBeCloseTo(100, 0);
  });
  it('does not put railways or park outlines in the walk graph', () => {
    expect(edges.some((e) => e.tags.railway || e.tags.leisure)).toBe(false);
  });
  it('dedupes elements merged from overlapping tiles', () => {
    const twice = mergeResponses([data, data]);
    expect(twice.nodes.size).toBe(osm.nodes.size);
    expect(buildGraph(twice, meta.center, { radiusM: meta.radiusM }).edges.length).toBe(base.edges.length);
  });
  it('splits a way at nodes missing from the download instead of bridging them', () => {
    const cut = mergeResponses([data]);
    const oak = [...cut.ways.values()].find((w) => w.tags?.name === 'Oak Avenue')!;
    cut.nodes.delete(oak.nodes![2]!); // node at x=-150
    const g = buildGraph(cut, meta.center, { radiusM: meta.radiusM });
    const oakEdges = g.edges.filter((e) => e.name === 'Oak Avenue');
    // The -300 → 0 block is dropped (its middle node is missing); -400→-300 and 0→300 survive.
    const total = oakEdges.reduce((s, e) => s + e.lengthM, 0);
    expect(total).toBeCloseTo(400, 0);
  });
  it('classifies major-road crossings', () => {
    const kinds = base.nodes.filter((n) => n.crossing !== 'none').map((n) => n.crossing);
    expect(kinds).toContain('signals'); // Main × Cottage (tagged)
    expect(kinds).toContain('unmarked'); // Main × Broadway (tagged unmarked)
    // Main St × Cottage sidewalk junction is 12 m from the signals → inferred signals, not unmarked
    expect(kinds.filter((k) => k === 'signals').length).toBeGreaterThanOrEqual(1);
  });
});

describe('edge features + scores (synthetic fixture)', () => {
  it('park footway borders grass and has amenities', () => {
    const walk = one('Green Walk', (e) => mid(e).x > -150);
    expect(walk.features.grassFraction).toBeGreaterThan(0.75); // park ends 40 m before Cottage Pl
    expect(walk.features.amenities.wasteBaskets + walk.features.amenities.bagDispensers).toBeGreaterThan(0);
    expect(walk.features.surface).toBe('unpaved');
  });
  it('Oak Ave east has street trees, west does not', () => {
    const east = one('Oak Avenue', (e) => mid(e).x > 0);
    const west = one('Oak Avenue', (e) => mid(e).x < -300);
    expect(east.features.treesPer100m).toBeGreaterThan(4);
    expect(west.features.treesPer100m).toBe(0);
  });
  it('Main St sidewalk is loud and crowded; Oak Ave is quiet', () => {
    const sw = one('Sidewalk · Main Street');
    expect(sw.features.distMajorRoadM).toBeLessThan(20);
    expect(sw.features.commercialPer100m).toBeGreaterThan(2);
    const oak = one('Oak Avenue', (e) => mid(e).x > 0);
    expect(q(oak).q).toBeGreaterThan(q(sw).q + 0.2);
  });
  it('Main St is scored below Oak Ave, Elm St near the railway is dinged for rail', () => {
    const main = one('Main Street', (e) => mid(e).x > 0 && mid(e).x < 300);
    const oak = one('Oak Avenue', (e) => mid(e).x > 0);
    expect(q(main).q).toBeLessThan(q(oak).q);
    const elm = one('Elm Street', (e) => mid(e).x > 0);
    expect(elm.features.distRailM).toBeLessThan(200);
  });
  it('busy Main St scores low under the everyday profile', () => {
    for (const e of byName('Main Street')) expect(q(e).q).toBeLessThan(0.2);
  });
  it('dog parks are neutral: Elm St west borders one but gets no grass credit', () => {
    const elmWest = one('Elm Street', (e) => mid(e).x < 0 && mid(e).x > -300);
    expect(elmWest.features.grassFraction).toBe(0);
    expect(elmWest.features.nearDogParkM).toBeLessThan(20);
  });
  it('counts tertiary crossings (Broadway) as busy-road crossings', () => {
    const onBroadway = base.nodes.filter((n) => n.crossing !== 'none' && Math.abs(proj.toXY(n.lat, n.lon)[0] + 300) < 1);
    expect(onBroadway.length).toBeGreaterThanOrEqual(2);
  });
  it('woodland relation provides canopy', () => {
    const broadwaySouth = edges.filter((e) => e.name === 'Broadway').sort((a, b) => mid(a).y - mid(b).y)[0]!;
    expect(broadwaySouth.features.canopyFraction).toBeGreaterThan(0);
  });
  it('building-mapped restaurant (out center) counts as commercial', () => {
    const main = one('Main Street', (e) => mid(e).x > 0 && mid(e).x < 300);
    expect(main.features.commercialPer100m).toBeGreaterThan(0);
  });
  it('excludes motorway, private, dog=no, construction, driveway and sidewalk-less secondary', () => {
    const reasons = new Set(edges.map((e) => q(e).excluded).filter(Boolean));
    expect([...reasons].sort()).toEqual(
      ['Busy road with no sidewalk', 'Driveway', 'Highway — no walking', 'No dogs allowed', 'Private — no access', 'Under construction'].sort(),
    );
    for (const e of byName('Hamilton Avenue')) expect(q(e).excluded).toBe('Busy road with no sidewalk');
  });
});

describe('describing unnamed paths', () => {
  it('names sidewalks after their street and park paths after their park', async () => {
    const { buildScoredGraphInputs } = await import('../routing/pipeline');
    const g = buildScoredGraphInputs([data], meta.center, meta.radiusM);
    const names = new Set(g.edges.map((e) => e.name));
    expect(names).toContain('Sidewalk · Main Street');
    expect(names).toContain('Path in Cottage Green');
    expect([...names].some((n) => /unnamed/i.test(n ?? ''))).toBe(false);
  });
});
