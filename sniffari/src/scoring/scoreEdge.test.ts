import { describe, expect, it } from 'vitest';
import { makeFeatures, NIGHT, NOON } from '../test/helpers';
import { PROFILES, PROFILE_ORDER } from './profiles';
import { edgeCost, effectiveEdgeWeights, scoreEdge, trafficVeto } from './scoreEdge';

describe('effectiveEdgeWeights', () => {
  it('normalises to 1, drops route-level crossings, and adds lighting only after dark', () => {
    for (const id of PROFILE_ORDER) {
      const day = effectiveEdgeWeights(PROFILES[id], NOON);
      const night = effectiveEdgeWeights(PROFILES[id], NIGHT);
      const sum = (w: object) => Object.values(w).reduce((a: number, b) => a + (b as number), 0);
      expect(sum(day)).toBeCloseTo(1);
      expect(sum(night)).toBeCloseTo(1);
      expect(day).not.toHaveProperty('crossings');
      expect(day).not.toHaveProperty('lighting');
      expect(night).toHaveProperty('lighting');
    }
  });
  it('keeps the SPEC ratios for the quiet profile', () => {
    const w = effectiveEdgeWeights(PROFILES.quiet, NOON);
    expect(w.quiet! / w.crowds!).toBeCloseTo(0.35 / 0.2);
  });
  it('applies slider overrides', () => {
    const w = effectiveEdgeWeights(PROFILES.quiet, NOON, { grass: 0 });
    expect(w).not.toHaveProperty('grass');
  });
});

describe('scoreEdge', () => {
  const w = effectiveEdgeWeights(PROFILES.quiet, NOON);
  it('scores an ideal street near 1 and an arterial low', () => {
    const ideal = makeFeatures({ grassFraction: 1, treesPer100m: 10 });
    const arterial = makeFeatures({ roadClass: 'primary', highway: 'primary', lanes: 4, distMajorRoadM: 0, commercialPer100m: 8 });
    expect(scoreEdge(ideal, w, NOON).q).toBeGreaterThan(0.95);
    expect(scoreEdge(arterial, w, NOON).q).toBeLessThan(0.5);
  });
  it('is a weighted mean of the factor scores', () => {
    const s = scoreEdge(makeFeatures(), w, NOON);
    let expected = 0;
    for (const [k, v] of Object.entries(w)) expected += v * s.factors[k as keyof typeof s.factors]!.score;
    expect(s.q).toBeCloseTo(expected);
  });
  it('zeroes excluded edges but still explains them', () => {
    const s = scoreEdge(makeFeatures({ dog: 'no' }), w, NOON);
    expect(s.q).toBe(0);
    expect(s.excluded).toMatch(/No dogs/);
    expect(s.factors.quiet).toBeDefined();
  });
  it('different profiles rank a leafy busy-ish street differently', () => {
    const leafy = makeFeatures({ roadClass: 'tertiary', grassFraction: 0.9, treesPer100m: 10, commercialPer100m: 4 });
    const qQuiet = scoreEdge(leafy, effectiveEdgeWeights(PROFILES.quiet, NOON), NOON).q;
    const qSniffy = scoreEdge(leafy, effectiveEdgeWeights(PROFILES.sniffy, NOON), NOON).q;
    expect(qSniffy).toBeGreaterThan(qQuiet);
  });
});

describe('traffic veto (busy streets must not score well)', () => {
  const w = effectiveEdgeWeights(PROFILES.everyday, NOON);
  it('leaves quiet streets alone and crushes arterials', () => {
    expect(trafficVeto(1)).toBe(1);
    expect(trafficVeto(0.7)).toBe(1);
    expect(trafficVeto(0.3)).toBeLessThan(0.6);
    expect(trafficVeto(0.1)).toBeLessThan(0.25);
  });
  it("Ricky's ideal street scores very high; a lit arterial with sidewalks scores very low", () => {
    const ideal = makeFeatures({ nearGrassM: 30, gradePct: 1 });
    const arterial = makeFeatures({
      roadClass: 'primary', highway: 'primary', lanes: 4, sidewalk: 'both', lit: 'yes', distMajorRoadM: 0, gradePct: 1,
    });
    expect(scoreEdge(ideal, w, NOON).q).toBeGreaterThan(0.85);
    expect(scoreEdge(arterial, w, NOON).q).toBeLessThan(0.15);
  });
  it('hills and a lack of green pull a quiet street down', () => {
    const flatGreen = scoreEdge(makeFeatures({ nearGrassM: 30, gradePct: 1 }), w, NOON).q;
    const steepBare = scoreEdge(makeFeatures({ roadClass: 'unclassified', gradePct: 10 }), w, NOON).q;
    expect(flatGreen - steepBare).toBeGreaterThan(0.3);
  });
});

describe('edgeCost', () => {
  it('is length for q=1, (1+α)×length for q=0, infinite when excluded', () => {
    const base = { factors: {}, amenities: { score: 0, reason: '' }, veto: 1 };
    expect(edgeCost(100, { ...base, q: 1, excluded: null })).toBe(100);
    expect(edgeCost(100, { ...base, q: 0, excluded: null })).toBe(400);
    expect(edgeCost(100, { ...base, q: 0, excluded: 'x' })).toBe(Infinity);
  });
});
