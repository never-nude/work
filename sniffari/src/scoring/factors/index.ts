import type { EdgeFactor, EdgeFactorKey } from '../../types';
import { crowds } from './crowds';
import { grass } from './grass';
import { lighting } from './lighting';
import { quiet } from './quiet';
import { shade } from './shade';
import { sidewalk } from './sidewalk';
import { surface } from './surface';

export const EDGE_FACTORS: Record<EdgeFactorKey, EdgeFactor> = {
  sidewalk,
  quiet,
  grass,
  shade,
  crowds,
  surface,
  lighting,
};

export { amenities } from './amenities';
export { crossingsFactor } from './crossings';
export { exclusionReason } from './rules';
