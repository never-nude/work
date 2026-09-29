import { useEffect, useRef } from 'react';
import {
  GeoJSONSource,
  Map as MLMap,
  Marker,
  NavigationControl,
  type ExpressionSpecification,
  type StyleSpecification,
} from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import './maplibreWorker';
import { useStore } from '../../state/store';
import { BASEMAP_STYLES, BLANK_DARK_STYLE } from './basemap';
import { EXCLUDED_COLOR, HEAT_STOPS } from './heatColors';

const EMPTY: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] };

const heatExpr: ExpressionSpecification = [
  'interpolate',
  ['linear'],
  ['get', 'q'],
  ...HEAT_STOPS.flatMap(([q, c]) => [q, c]),
] as unknown as ExpressionSpecification;

/** Line width by zoom, scaled by k (zoom must stay the top-level interpolate input). */
const widthAt = (k: number, add = 0): ExpressionSpecification => [
  'interpolate', ['exponential', 1.6], ['zoom'],
  13, 1.5 * k + add, 16, 4 * k + add, 19, 12 * k + add,
];
const widthExpr = widthAt(1);

function radiusCircle(lat: number, lon: number, r: number): GeoJSON.Feature<GeoJSON.LineString> {
  const pts: [number, number][] = [];
  const kx = 111_320 * Math.cos((lat * Math.PI) / 180);
  for (let i = 0; i <= 96; i++) {
    const a = (i / 96) * 2 * Math.PI;
    pts.push([lon + (Math.cos(a) * r) / kx, lat + (Math.sin(a) * r) / 110_574]);
  }
  return { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: pts } };
}

function addOverlay(map: MLMap) {
  if (map.getSource('edges')) return;
  map.addSource('radius', { type: 'geojson', data: EMPTY });
  map.addSource('edges', { type: 'geojson', data: EMPTY, promoteId: 'id' });
  map.addSource('crossings', { type: 'geojson', data: EMPTY });

  map.addLayer({
    id: 'radius',
    type: 'line',
    source: 'radius',
    paint: { 'line-color': '#a78bfa', 'line-opacity': 0.5, 'line-width': 1.5, 'line-dasharray': [3, 3] },
  });
  map.addLayer({
    id: 'edges-excluded',
    type: 'line',
    source: 'edges',
    filter: ['<', ['get', 'q'], 0],
    layout: { 'line-cap': 'round' },
    paint: { 'line-color': EXCLUDED_COLOR, 'line-width': widthAt(0.6), 'line-dasharray': [1, 1.5] },
  });
  map.addLayer({
    id: 'edges-selected',
    type: 'line',
    source: 'edges',
    filter: ['==', ['get', 'id'], -2],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#ffffff', 'line-width': widthAt(1, 6), 'line-opacity': 0.9 },
  });
  map.addLayer({
    id: 'edges',
    type: 'line',
    source: 'edges',
    filter: ['>=', ['get', 'q'], 0],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': heatExpr, 'line-width': widthExpr },
  });
  map.addLayer({
    id: 'crossings',
    type: 'circle',
    source: 'crossings',
    minzoom: 15,
    paint: {
      'circle-radius': ['interpolate', ['linear'], ['zoom'], 15, 3, 18, 7],
      'circle-color': [
        'match',
        ['get', 'kind'],
        'signals', '#22e3a0',
        'marked', '#ffd23f',
        'rail', '#a78bfa',
        '#ff3b5c',
      ] as unknown as ExpressionSpecification,
      'circle-stroke-color': '#101017',
      'circle-stroke-width': 1.5,
    },
  });
}

export function MapView() {
  const container = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MLMap | null>(null);
  const markerRef = useRef<Marker | null>(null);

  const start = useStore((s) => s.start);
  const radiusM = useStore((s) => s.radiusM);
  const heatmap = useStore((s) => s.heatmap);
  const selectedId = useStore((s) => s.selectedId);
  const selected = useStore((s) => s.selected);

  // Create the map once.
  useEffect(() => {
    if (!container.current) return;
    const { start: s } = useStore.getState();
    let styleIdx = 0;
    const map = new MLMap({
      container: container.current,
      style: BASEMAP_STYLES[0]!,
      center: [s.lon, s.lat],
      zoom: 14.5,
      attributionControl: { compact: true },
    });
    mapRef.current = map;
    map.addControl(new NavigationControl({ showCompass: false }), 'top-right');

    const fallback = () => {
      styleIdx++;
      const next: string | StyleSpecification = BASEMAP_STYLES[styleIdx] ?? BLANK_DARK_STYLE;
      if (styleIdx <= BASEMAP_STYLES.length) map.setStyle(next, { diff: false });
    };
    // A style that fails to fetch fires 'error' before any 'style.load'.
    let styleLoaded = false;
    map.on('error', (e) => {
      if (!styleLoaded) fallback();
      else console.warn('map error', e.error?.message);
    });
    map.on('style.load', () => {
      styleLoaded = true;
      addOverlay(map);
      syncData(map);
    });

    // One generous hit box instead of per-layer handlers: thin lines are hard to tap one-handed.
    map.on('click', (e) => {
      const layers = ['edges', 'edges-excluded'].filter((l) => map.getLayer(l));
      const hits = map.queryRenderedFeatures(
        [
          [e.point.x - 12, e.point.y - 12],
          [e.point.x + 12, e.point.y + 12],
        ],
        { layers },
      );
      useStore.getState().inspect(hits.length ? Number(hits[0]!.properties.id) : null);
    });
    for (const l of ['edges', 'edges-excluded']) {
      map.on('mouseenter', l, () => (map.getCanvas().style.cursor = 'pointer'));
      map.on('mouseleave', l, () => (map.getCanvas().style.cursor = ''));
    }

    return () => {
      map.remove();
      mapRef.current = null;
      markerRef.current = null; // StrictMode remounts: don't keep a marker bound to the removed map
    };
  }, []);

  function syncData(map: MLMap) {
    const s = useStore.getState();
    (map.getSource('edges') as GeoJSONSource | undefined)?.setData(s.heatmap?.edges ?? EMPTY);
    (map.getSource('crossings') as GeoJSONSource | undefined)?.setData(s.heatmap?.crossings ?? EMPTY);
    (map.getSource('radius') as GeoJSONSource | undefined)?.setData(radiusCircle(s.start.lat, s.start.lon, s.radiusM));
    if (map.getLayer('edges-selected')) map.setFilter('edges-selected', ['==', ['get', 'id'], s.selectedId ?? -2]);
  }

  useEffect(() => {
    const map = mapRef.current;
    if (map?.isStyleLoaded()) syncData(map);
  }, [heatmap, radiusM, start, selectedId]);

  // Keep the inspected street visible above the bottom sheet (phone) or left of the side panel (desktop).
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !selected) return;
    const { lat, lon } = selected.mid;
    const p = map.project([lon, lat]);
    const { clientWidth: w, clientHeight: h } = map.getContainer();
    const phone = w < 820;
    const visible = phone ? p.y > 80 && p.y < h * 0.4 : p.x > 20 && p.x < w - 420;
    if (!visible) map.easeTo({ center: [lon, lat], offset: phone ? [0, -h * 0.28] : [-200, 0], duration: 400 });
  }, [selected]);

  // Start marker + recentre.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!markerRef.current) {
      const el = document.createElement('div');
      el.className = 'start-marker';
      markerRef.current = new Marker({ element: el }).setLngLat([start.lon, start.lat]).addTo(map);
    } else {
      markerRef.current.setLngLat([start.lon, start.lat]);
    }
    map.easeTo({ center: [start.lon, start.lat], duration: 600 });
  }, [start]);

  return <div ref={container} className="map" />;
}
