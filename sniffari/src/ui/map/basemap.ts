import type { StyleSpecification } from 'maplibre-gl';

/**
 * OpenFreeMap's hosted styles (keyless). "dark" is tried first, "fiord" (a
 * dark blue-grey style) second. If neither loads — offline, blocked — we fall
 * back to a plain dark canvas so the heatmap still renders.
 */
export const BASEMAP_STYLES = [
  'https://tiles.openfreemap.org/styles/dark',
  'https://tiles.openfreemap.org/styles/fiord',
];

export const BLANK_DARK_STYLE: StyleSpecification = {
  version: 8,
  sources: {},
  layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#101017' } }],
};
