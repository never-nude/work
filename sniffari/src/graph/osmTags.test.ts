import { describe, expect, it } from 'vitest';
import { isGraphWay, parseLit, parseMaxspeedMph, parseSidewalk, parseSurface } from './osmTags';

describe('parseSidewalk', () => {
  it.each([
    [{ sidewalk: 'both' }, 'residential', 'both'],
    [{ sidewalk: 'right' }, 'residential', 'one'],
    [{ sidewalk: 'separate' }, 'residential', 'separate'],
    [{ sidewalk: 'no' }, 'residential', 'none'],
    [{ 'sidewalk:both': 'yes' }, 'residential', 'both'],
    [{ 'sidewalk:left': 'yes', 'sidewalk:right': 'no' }, 'residential', 'one'],
    [{ 'sidewalk:left': 'separate', 'sidewalk:right': 'separate' }, 'residential', 'separate'],
    [{ 'sidewalk:left': 'no', 'sidewalk:right': 'no' }, 'residential', 'none'],
    [{}, 'residential', 'unknown'],
    [{}, 'footway', 'dedicated'],
  ] as const)('%o on %s → %s', (tags, rc, expected) => {
    expect(parseSidewalk(tags, rc)).toBe(expected);
  });
});

describe('parseMaxspeedMph', () => {
  it('reads mph and converts bare km/h', () => {
    expect(parseMaxspeedMph('25 mph')).toBe(25);
    expect(parseMaxspeedMph('50')).toBeCloseTo(31.1, 1);
    expect(parseMaxspeedMph('signals')).toBeNull();
    expect(parseMaxspeedMph(undefined)).toBeNull();
  });
});

describe('parseSurface / parseLit / isGraphWay', () => {
  it('classifies surfaces with sensible defaults', () => {
    expect(parseSurface({ surface: 'gravel' }, 'footway')).toBe('unpaved');
    expect(parseSurface({ surface: 'asphalt' }, 'footway')).toBe('paved');
    expect(parseSurface({}, 'residential')).toBe('paved');
    expect(parseSurface({}, 'footway')).toBe('unknown');
  });
  it('reads lit', () => {
    expect(parseLit('yes')).toBe('yes');
    expect(parseLit('24/7')).toBe('yes');
    expect(parseLit('no')).toBe('no');
    expect(parseLit(undefined)).toBe('unknown');
  });
  it('filters non-walkable highway values', () => {
    expect(isGraphWay({ highway: 'residential' })).toBe(true);
    expect(isGraphWay({ highway: 'proposed' })).toBe(false);
    expect(isGraphWay({ highway: 'platform' })).toBe(false);
    expect(isGraphWay({ building: 'yes' })).toBe(false);
  });
});
