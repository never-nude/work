import type { LatLon } from '../types';

export interface FixtureMeta {
  name: string;
  label: string;
  center: LatLon;
  radiusM: number;
}

const metas = import.meta.glob<FixtureMeta>('../../fixtures/*.meta.json', { import: 'default', eager: true });

/** Fixtures bundled with the app (synthetic always; white-plains after `npm run fixture:fetch`). */
export const FIXTURES: FixtureMeta[] = Object.values(metas).sort((a, b) =>
  a.name === 'synthetic' ? 1 : b.name === 'synthetic' ? -1 : a.name.localeCompare(b.name),
);

/** The project's real-world test location (CLAUDE.md). */
export const HOME_FIXTURE = {
  label: 'AVE Hamilton Green, 25 Cottage Pl',
  query: '25 Cottage Place, White Plains, NY 10601',
  // Approximate downtown White Plains; replaced by the geocoded point on first live load.
  approx: { lat: 41.0335, lon: -73.763 } satisfies LatLon,
};
