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
  map.addSource('routes', { type: 'geojson', data: EMPTY });

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
    id: 'routes-alt',
    type: 'line',
    source: 'routes',
    filter: ['!=', ['get', 'selected'], true],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#fdf6e9', 'line-opacity': 0.55, 'line-width': widthAt(1.1, 2), 'line-dasharray': [1.5, 1.2] },
  });
  map.addLayer({
    id: 'routes-casing',
    type: 'line',
    source: 'routes',
    filter: ['==', ['get', 'selected'], true],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#16131c', 'line-width': widthAt(1.6, 8) },
  });
  map.addLayer({
    id: 'routes-selected',
    type: 'line',
    source: 'routes',
    filter: ['==', ['get', 'selected'], true],
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#ae83fa', 'line-width': widthAt(1.3, 4) },
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
  const routes = useStore((s) => s.routes);
  const routeIndex = useStore((s) => s.routeIndex);
  const endPoint = useStore((s) => s.endPoint);
  const endMarkerRef = useRef<Marker | null>(null);
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
    useStore.setState({
      getViewBounds: () => {
        const b = map.getBounds();
        return [b.getSouth(), b.getWest(), b.getNorth(), b.getEast()];
      },
    });

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
      const st = useStore.getState();
      if (st.pickingEnd) {
        st.setEndPoint({ lat: e.lngLat.lat, lon: e.lngLat.lng, label: 'Chosen end point' });
        return;
      }
      const box: [[number, number], [number, number]] = [
        [e.point.x - 12, e.point.y - 12],
        [e.point.x + 12, e.point.y + 12],
      ];
      if (st.routes.length && map.getLayer('routes-alt')) {
        const hit = map.queryRenderedFeatures(box, { layers: ['routes-selected', 'routes-alt'] })[0];
        if (hit) {
          st.selectRoute(Number(hit.properties.index));
          return;
        }
      }
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
      endMarkerRef.current = null;
      useStore.setState({ getViewBounds: null });
      markerRef.current = null; // StrictMode remounts: don't keep a marker bound to the removed map
    };
  }, []);

  function syncData(map: MLMap) {
    const s = useStore.getState();
    (map.getSource('edges') as GeoJSONSource | undefined)?.setData(s.heatmap?.edges ?? EMPTY);
    (map.getSource('crossings') as GeoJSONSource | undefined)?.setData(s.heatmap?.crossings ?? EMPTY);
    (map.getSource('radius') as GeoJSONSource | undefined)?.setData(radiusCircle(s.start.lat, s.start.lon, s.radiusM));
    if (map.getLayer('edges-selected')) map.setFilter('edges-selected', ['==', ['get', 'id'], s.selectedId ?? -2]);
    (map.getSource('routes') as GeoJSONSource | undefined)?.setData({
      type: 'FeatureCollection',
      features: s.routes.map((r, i) => ({
        type: 'Feature',
        properties: { index: i, selected: i === s.routeIndex },
        geometry: { type: 'LineString', coordinates: r.coords },
      })),
    });
    // Heatmap steps back while routes are shown.
    const dim = s.routes.length > 0;
    if (map.getLayer('edges')) map.setPaintProperty('edges', 'line-opacity', dim ? 0.3 : 1);
    if (map.getLayer('edges-excluded')) map.setPaintProperty('edges-excluded', 'line-opacity', dim ? 0.25 : 1);
    if (map.getLayer('crossings')) map.setPaintProperty('crossings', 'circle-opacity', dim ? 0.5 : 1);
  }

  useEffect(() => {
    const map = mapRef.current;
    if (map?.isStyleLoaded()) syncData(map);
  }, [heatmap, radiusM, start, selectedId, routes, routeIndex]);

  // Frame the selected route (leave room for the sheet on phones / panel on desktop).
  useEffect(() => {
    const map = mapRef.current;
    const r = routes[routeIndex];
    if (!map || !r) return;
    let w = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
    for (const [lon, lat] of r.coords) {
      w = Math.min(w, lon); e = Math.max(e, lon); s = Math.min(s, lat); n = Math.max(n, lat);
    }
    const { clientWidth: cw, clientHeight: ch } = map.getContainer();
    const phone = cw < 820;
    map.fitBounds([[w, s], [e, n]], {
      padding: phone ? { top: 90, bottom: ch * 0.5, left: 30, right: 30 } : { top: 90, bottom: 40, left: 40, right: 440 },
      duration: 600,
      maxZoom: 17,
    });
  }, [routes, routeIndex]);

  // End-point marker for "somewhere else" walks.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!endPoint) {
      endMarkerRef.current?.remove();
      endMarkerRef.current = null;
      return;
    }
    if (!endMarkerRef.current) {
      const el = document.createElement('div');
      el.className = 'end-marker';
      endMarkerRef.current = new Marker({ element: el, anchor: 'bottom' }).setLngLat([endPoint.lon, endPoint.lat]).addTo(map);
    } else endMarkerRef.current.setLngLat([endPoint.lon, endPoint.lat]);
  }, [endPoint]);

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
    if (!useStore.getState().routes.length) map.easeTo({ center: [start.lon, start.lat], duration: 600 });
  }, [start]);

  return <div ref={container} className="map" />;
}
