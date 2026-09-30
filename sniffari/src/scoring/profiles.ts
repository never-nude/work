import type { Profile, ProfileId } from '../types';

/**
 * Preset weights from SPEC §5. Weights are relative and normalised at scoring
 * time over whichever factors are in play (e.g. lighting only after dark,
 * crossings only at route level), so they needn't sum to 1.
 *
 * `lighting` is the weight applied after sunset; it is ignored in daylight.
 */
export const PROFILES: Record<ProfileId, Profile> = {
  // Mike's brief (2026-09-29), built around Ricky: quiet residential streets with
  // sidewalks, a green patch nearby to do his business, not hilly, safe crossings.
  everyday: {
    id: 'everyday',
    name: 'Everyday',
    blurb: 'Quiet streets with sidewalks, green nearby for potty stops, flat, safe crossings.',
    weights: { quiet: 0.3, grass: 0.25, sidewalk: 0.2, terrain: 0.15, crossings: 0.15, crowds: 0.1, shade: 0.05, lighting: 0.15 },
    amenityBonus: 1,
  },
  quiet: {
    id: 'quiet',
    name: 'Quiet / reactive',
    blurb: 'Avoids traffic, crowds and scary crossings.',
    weights: { quiet: 0.35, crowds: 0.2, crossings: 0.15, sidewalk: 0.15, grass: 0.1, shade: 0.05, terrain: 0.05, lighting: 0.15 },
    amenityBonus: 1,
  },
  sniffy: {
    id: 'sniffy',
    name: 'Sniffy explorer',
    blurb: 'Maximum grass, trees and interesting edges.',
    weights: { grass: 0.35, shade: 0.15, quiet: 0.15, sidewalk: 0.15, crowds: 0.1, crossings: 0.1, terrain: 0.05, lighting: 0.15 },
    amenityBonus: 1,
  },
  // SPEC gives no numbers for Potty break — these are a proposal, see docs/PLAN.md §6.
  potty: {
    id: 'potty',
    name: 'Potty break',
    blurb: 'Short. Nearest good grass, few crossings, straight home.',
    weights: { grass: 0.4, crossings: 0.2, quiet: 0.2, sidewalk: 0.2, terrain: 0.1, lighting: 0.15 },
    amenityBonus: 1.5,
    shortWalk: true,
  },
  senior: {
    id: 'senior',
    name: 'Senior / hot day',
    blurb: 'Shade, easy surfaces, benches to rest.',
    // SPEC §5 lists elevation "later" for seniors; now that terrain exists it gets real weight.
    weights: { shade: 0.3, terrain: 0.25, surface: 0.2, sidewalk: 0.2, quiet: 0.15, lighting: 0.15 },
    amenityBonus: 1.5,
  },
};

export const PROFILE_ORDER: ProfileId[] = ['everyday', 'quiet', 'sniffy', 'potty', 'senior'];
