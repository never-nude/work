import { describe, expect, it } from 'vitest';
import { makeFeatures, NIGHT, NOON } from '../../test/helpers';
import { amenities } from './amenities';
import { crossingsFactor } from './crossings';
import { crowdMultiplier, crowds } from './crowds';
import { grass } from './grass';
import { lighting } from './lighting';
import { quiet } from './quiet';
import { exclusionReason } from './rules';
import { shade } from './shade';
import { sidewalk } from './sidewalk';
import { surface } from './surface';
import { EDGE_FACTORS } from '.';

describe('every edge factor', () => {
  const variants = [
    makeFeatures(),
    makeFeatures({ roadClass: 'primary', sidewalk: 'none', lanes: 6, maxspeedMph: 55, distMajorRoadM: 0 }),
    makeFeatures({ roadClass: 'footway', sidewalk: 'dedicated', grassFraction: 1, treesPer100m: 40, canopyFraction: 1 }),
    makeFeatures({ commercialPer100m: 50, busStops: 9, distStationM: 0, lit: 'no', surface: 'unknown' }),
  ];
  for (const [key, fn] of Object.entries(EDGE_FACTORS)) {
    it(`${key} returns a score in [0,1] and a non-empty reason`, () => {
      for (const f of variants) {
        for (const ctx of [NOON, NIGHT]) {
          const r = fn(f, ctx);
          expect(r.score).toBeGreaterThanOrEqual(0);
          expect(r.score).toBeLessThanOrEqual(1);
          expect(r.reason.length).toBeGreaterThan(0);
        }
      }
    });
  }
});

describe('sidewalk', () => {
  it('prefers dedicated paths and full sidewalks', () => {
    expect(sidewalk(makeFeatures({ roadClass: 'footway', sidewalk: 'dedicated', footwayType: 'sidewalk' }), NOON).score).toBe(1);
    expect(sidewalk(makeFeatures({ sidewalk: 'both' }), NOON).score).toBe(1);
    expect(sidewalk(makeFeatures({ sidewalk: 'one' }), NOON).score).toBeLessThan(1);
  });
  it('treats a quiet road without sidewalk as ~0.5 (SPEC)', () => {
    expect(sidewalk(makeFeatures({ sidewalk: 'none' }), NOON).score).toBeCloseTo(0.5, 1);
  });
  it('gives unmapped residential sidewalks the benefit of the doubt', () => {
    const r = sidewalk(makeFeatures({ sidewalk: 'unknown' }), NOON);
    expect(r.score).toBeGreaterThan(0.5);
    expect(r.reason).toMatch(/not mapped/);
  });
});

describe('quiet', () => {
  it('orders road classes as in SPEC §4', () => {
    const s = (rc: Parameters<typeof makeFeatures>[0]) => quiet(makeFeatures(rc), NOON).score;
    expect(s({ roadClass: 'residential' })).toBe(1);
    expect(s({ roadClass: 'tertiary' })).toBeCloseTo(0.6);
    expect(s({ roadClass: 'secondary' })).toBeCloseTo(0.3);
    expect(s({ roadClass: 'primary' })).toBeCloseTo(0.1);
  });
  it('penalises a footpath right beside a major road', () => {
    const r = quiet(makeFeatures({ roadClass: 'footway', sidewalk: 'dedicated', distMajorRoadM: 10 }), NOON);
    expect(r.score).toBeLessThanOrEqual(0.35);
    expect(r.reason).toMatch(/major road/);
  });
  it('penalises speed, lanes and rail', () => {
    const base = quiet(makeFeatures({ roadClass: 'tertiary' }), NOON).score;
    expect(quiet(makeFeatures({ roadClass: 'tertiary', maxspeedMph: 45 }), NOON).score).toBeLessThan(base);
    expect(quiet(makeFeatures({ roadClass: 'tertiary', lanes: 4 }), NOON).score).toBeLessThan(base);
    expect(quiet(makeFeatures({ roadClass: 'tertiary', distRailM: 30 }), NOON).score).toBeLessThan(base);
  });
});

describe('grass', () => {
  it('scales with the fraction bordering grass', () => {
    const lo = grass(makeFeatures({ grassFraction: 0.2 }), NOON).score;
    const hi = grass(makeFeatures({ grassFraction: 0.9 }), NOON).score;
    expect(hi).toBeGreaterThan(lo);
    expect(grass(makeFeatures({ grassFraction: 1 }), NOON).score).toBe(1);
  });
  it('gives residential streets an unmapped-lawn baseline, but not arterials', () => {
    expect(grass(makeFeatures({ roadClass: 'residential' }), NOON).score).toBe(0.3);
    expect(grass(makeFeatures({ roadClass: 'primary' }), NOON).score).toBe(0);
  });
});

describe('shade', () => {
  it('is 0 without trees and saturates with many', () => {
    expect(shade(makeFeatures(), NOON).score).toBe(0);
    expect(shade(makeFeatures({ treesPer100m: 20 }), NOON).score).toBe(1);
    expect(shade(makeFeatures({ canopyFraction: 0.5 }), NOON).score).toBeCloseTo(0.5);
  });
});

describe('crowds', () => {
  it('drops with commercial density and more so at dinner time', () => {
    const f = makeFeatures({ commercialPer100m: 5 });
    const noon = crowds(f, { hour: 15, isDark: false }).score;
    const dinner = crowds(f, { hour: 19, isDark: false }).score;
    const night = crowds(f, { hour: 2, isDark: true }).score;
    expect(dinner).toBeLessThan(noon);
    expect(night).toBeGreaterThan(noon);
    expect(crowds(makeFeatures(), NOON).score).toBe(1);
  });
  it('knows rush hour, lunch and late night', () => {
    expect(crowdMultiplier(8)).toBeGreaterThan(1);
    expect(crowdMultiplier(12)).toBeGreaterThan(1);
    expect(crowdMultiplier(3)).toBeLessThan(1);
  });
  it('penalises stations and bus stops', () => {
    expect(crowds(makeFeatures({ distStationM: 100 }), NOON).score).toBeLessThan(1);
    expect(crowds(makeFeatures({ busStops: 2 }), NOON).score).toBeLessThan(1);
  });
});

describe('surface', () => {
  it('prefers unpaved in heat and paved after rain', () => {
    const hot = { hour: 14, isDark: false, weather: { tempF: 90, uvIndex: 9, precipLast24hMm: 0, snowLast48hCm: 0 } };
    const wet = { hour: 14, isDark: false, weather: { tempF: 60, uvIndex: 2, precipLast24hMm: 20, snowLast48hCm: 0 } };
    expect(surface(makeFeatures({ surface: 'unpaved' }), hot).score).toBeGreaterThan(surface(makeFeatures({ surface: 'paved' }), hot).score);
    expect(surface(makeFeatures({ surface: 'unpaved' }), wet).score).toBeLessThan(surface(makeFeatures({ surface: 'paved' }), wet).score);
  });
});

describe('lighting', () => {
  it('trusts lit tags and guesses for untagged streets vs paths', () => {
    expect(lighting(makeFeatures({ lit: 'yes' }), NIGHT).score).toBe(1);
    expect(lighting(makeFeatures({ lit: 'no' }), NIGHT).score).toBeLessThan(0.2);
    expect(lighting(makeFeatures(), NIGHT).score).toBeGreaterThan(
      lighting(makeFeatures({ roadClass: 'path', sidewalk: 'dedicated' }), NIGHT).score,
    );
  });
});

describe('amenities', () => {
  it('is a capped bonus that lists what it found', () => {
    expect(amenities(makeFeatures(), NOON).score).toBe(0);
    const r = amenities(makeFeatures({ amenities: { wasteBaskets: 1, bagDispensers: 1, water: 0, dogWater: 0, benches: 2, dogFriendly: 0 } }), NOON);
    expect(r.score).toBe(1);
    expect(r.reason).toBe('1 bin, 1 bag dispenser, 2 benches');
  });
});

describe('exclusions (rules + hazards)', () => {
  it.each([
    [{ roadClass: 'motorway' as const }, /Highway/],
    [{ roadClass: 'trunk' as const }, /Highway/],
    [{ construction: true }, /construction/],
    [{ dog: 'no' }, /No dogs/],
    [{ access: 'private' }, /Private/],
    [{ access: 'no' }, /Private/],
    [{ foot: 'no' }, /No pedestrians/],
    [{ roadClass: 'secondary' as const, sidewalk: 'none' as const }, /no sidewalk/],
    [{ service: 'driveway' }, /Driveway/],
  ])('%o is excluded', (over, re) => {
    expect(exclusionReason(makeFeatures(over))).toMatch(re);
  });
  it('allows leashed dogs, foot=yes on private roads, and secondary roads with unknown sidewalks', () => {
    expect(exclusionReason(makeFeatures({ dog: 'leashed' }))).toBeNull();
    expect(exclusionReason(makeFeatures({ access: 'private', foot: 'yes' }))).toBeNull();
    expect(exclusionReason(makeFeatures({ roadClass: 'secondary', sidewalk: 'unknown' }))).toBeNull();
  });
});

describe('crossings (route-level)', () => {
  it('is 1 with no busy crossings', () => {
    expect(crossingsFactor([], 2000).score).toBe(1);
    expect(crossingsFactor(['none', 'none'], 2000).score).toBe(1);
  });
  it('orders signals > marked > unmarked', () => {
    const s = (k: 'signals' | 'marked' | 'unmarked') => crossingsFactor([k, k], 2000).score;
    expect(s('signals')).toBeGreaterThan(s('marked'));
    expect(s('marked')).toBeGreaterThan(s('unmarked'));
  });
  it('normalises by route length and explains itself', () => {
    expect(crossingsFactor(['marked'], 4000).score).toBeGreaterThan(crossingsFactor(['marked'], 1000).score);
    expect(crossingsFactor(['signals', 'signals', 'unmarked'], 2000).reason).toBe(
      '2 signalised, 1 unmarked crossings of busy roads',
    );
  });
});
