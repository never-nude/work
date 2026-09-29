import type { EdgeFactorKey } from '../../types';

export const FACTOR_LABEL: Record<EdgeFactorKey, string> = {
  sidewalk: 'Sidewalk',
  quiet: 'Quiet',
  grass: 'Grass',
  shade: 'Shade',
  crowds: 'Calm (few crowds)',
  surface: 'Surface',
  lighting: 'Lighting',
};

export const FACTOR_ORDER: EdgeFactorKey[] = ['quiet', 'sidewalk', 'grass', 'shade', 'crowds', 'surface', 'lighting'];
