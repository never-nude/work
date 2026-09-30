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
import { haversineM } from '../../graph/geo';

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
    paint: { 'line-color': '#ae83fa', 'line-opacity': 0.8, 'line-width': 2.5, 'line-dasharray': [2, 2] },
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
  const viewArea = useStore((s) => s.viewArea);
  const me = useStore((s) => s.me);
  const meMarkerRef = useRef<Marker | null>(null);
  const pin = useStore((s) => s.pin);
  const pinMarkerRef = useRef<Marker | null>(null);
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
      zoom: 14.3,
      attributionControl: { compact: true },
      dragRotate: false,
      pitchWithRotate: false,
    });
    mapRef.current = map;
    map.addControl(new NavigationControl({ showCompass: false }), 'top-right');
    const viewBounds = (): [number, number, number, number] => {
      const b = map.getBounds();
      return [b.getSouth(), b.getWest(), b.getNorth(), b.getEast()];
    };
    useStore.setState({
      getViewBounds: viewBounds,
      flyTo: (p, zoom) => map.flyTo({ center: [p.lon, p.lat], zoom: zoom ?? map.getZoom(), duration: 900 }),
    });
    // The walk area: a circle in the middle of the visible map (above the phone sheet,
    // left of the desktop panel). Drag to move it, pinch to resize it.
    const walkArea = () => {
      const { clientWidth: w, clientHeight: h } = map.getContainer();
      const phone = w < 820;
      const visW = phone ? w : w - 400;
      const top = 80;
      const bottom = phone ? h - 150 : h;
      const cx = visW / 2;
      const cy = (top + bottom) / 2;
      const rPx = Math.max(40, 0.44 * Math.min(visW, bottom - top));
      const c = map.unproject([cx, cy]);
      const e = map.unproject([cx + rPx, cy]);
      const center = { lat: c.lat, lon: c.lng };
      return { center, radiusM: haversineM(center, { lat: e.lat, lon: e.lng }) };
    };
    const drawWalk = () => {
      const a = walkArea();
      (map.getSource('radius') as GeoJSONSource | undefined)?.setData(radiusCircle(a.center.lat, a.center.lon, a.radiusM));
    };
    map.on('move', drawWalk);
    map.on('moveend', () => useStore.getState().onViewChanged(walkArea()));
    void viewBounds;

    // Drop a pin: right-click / two-finger click on desktop, long-press on touch.
    map.on('contextmenu', (e) => {
      e.preventDefault();
      useStore.getState().dropPin({ lat: e.lngLat.lat, lon: e.lngLat.lng });
    });
    let pressTimer: ReturnType<typeof setTimeout> | undefined;
    let pressStart: { x: number; y: number } | null = null;
    map.on('touchstart', (e) => {
      if (e.originalEvent.touches.length !== 1) return clearTimeout(pressTimer);
      pressStart = { x: e.point.x, y: e.point.y };
      const at = e.lngLat;
      pressTimer = setTimeout(() => {
        navigator.vibrate?.(15);
        useStore.getState().dropPin({ lat: at.lat, lon: at.lng });
      }, 550);
    });
    map.on('touchmove', (e) => {
      if (pressStart && Math.hypot(e.point.x - pressStart.x, e.point.y - pressStart.y) > 8) clearTimeout(pressTimer);
    });
    map.on('touchend', () => clearTimeout(pressTimer));
    map.on('touchcancel', () => clearTimeout(pressTimer));
    map.on('movestart', () => clearTimeout(pressTimer));
    map.once('load', () => {
      drawWalk();
      useStore.getState().onViewChanged(walkArea());
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
      if (st.pin) {
        st.clearPin();
        return;
      }
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
      meMarkerRef.current = null;
      pinMarkerRef.current = null;
      useStore.setState({ getViewBounds: null, flyTo: null });
      markerRef.current = null; // StrictMode remounts: don't keep a marker bound to the removed map
    };
  }, []);

  function syncData(map: MLMap) {
    const s = useStore.getState();
    (map.getSource('edges') as GeoJSONSource | undefined)?.setData(s.heatmap?.edges ?? EMPTY);
    (map.getSource('crossings') as GeoJSONSource | undefined)?.setData(s.heatmap?.crossings ?? EMPTY);
    // The circle is the walk area (drawn live on move; here for style reloads).
    const a = s.viewArea;
    (map.getSource('radius') as GeoJSONSource | undefined)?.setData(a ? radiusCircle(a.center.lat, a.center.lon, a.radiusM) : EMPTY);
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
  }, [heatmap, viewArea, start, selectedId, routes, routeIndex]);

  // Dropped pin.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!pin) {
      pinMarkerRef.current?.remove();
      pinMarkerRef.current = null;
      return;
    }
    if (!pinMarkerRef.current) {
      const el = document.createElement('div');
      el.className = 'drop-pin';
      pinMarkerRef.current = new Marker({ element: el, anchor: 'bottom' }).setLngLat([pin.lon, pin.lat]).addTo(map);
    } else pinMarkerRef.current.setLngLat([pin.lon, pin.lat]);
  }, [pin]);

  // Live "you are here" dot; while navigating the map follows the walker.
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !me) return;
    if (useStore.getState().nav && !map.isMoving()) map.easeTo({ center: [me.lon, me.lat], zoom: Math.max(map.getZoom(), 17), duration: 800 });
    if (!meMarkerRef.current) {
      const el = document.createElement('div');
      el.className = 'me-marker';
      meMarkerRef.current = new Marker({ element: el }).setLngLat([me.lon, me.lat]).addTo(map);
    } else meMarkerRef.current.setLngLat([me.lon, me.lat]);
  }, [me]);

  // Frame the selected route (leave room for the sheet on phones / panel on desktop).
  useEffect(() => {
    const map = mapRef.current;
    const r = routes[routeIndex];
    if (!map || !r || useStore.getState().nav) return;
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
  }, [start]);

  return <div ref={container} className="map" />;
}
