import { create } from 'zustand';
import type { EdgeDetail, DataSource, HeatmapPayload, Stage } from '../routing/protocol';
import type { LatLon, ProfileId, Route, ScoringContext } from '../types';
import type { Bounds, PlanRequest } from '../routing/loopGenerator';
import { haversineM } from '../graph/geo';
import { reverseGeocode } from '../data/geocode';
import { cumulative, project } from '../routing/progress';
import { FIXTURES, HOME_FIXTURE } from './fixtures';
import { RoutingWorker } from './workerClient';

export type TimePreset = 'now' | 'rush' | 'lunch' | 'evening' | 'night';

export const TIME_PRESETS: Record<TimePreset, { label: string; hour?: number; dark?: boolean }> = {
  now: { label: 'Now' },
  rush: { label: '8 am', hour: 8, dark: false },
  lunch: { label: 'Noon', hour: 12, dark: false },
  evening: { label: '6 pm', hour: 18, dark: false },
  night: { label: '10 pm', hour: 22, dark: true },
};

/** Phase 4 replaces this with Open-Meteo sunrise/sunset. */
function contextFor(preset: TimePreset, dogParks: boolean, now = new Date()): ScoringContext {
  const p = TIME_PRESETS[preset];
  const hour = p.hour ?? now.getHours();
  const isDark = p.dark ?? (hour < 7 || hour >= 19);
  return { hour, isDark, dogParks };
}

export interface Place extends LatLon {
  label: string;
}

interface Progress {
  stage: Stage;
  done: number;
  total: number;
  message: string;
}

export const PACES = {
  sniff: { label: 'Sniff walk', mph: 1.5 },
  easy: { label: 'Easy stroll', mph: 2.2 },
  brisk: { label: 'Brisk', mph: 3.0 },
} as const;
export type PaceId = keyof typeof PACES;
export const WALK_MINUTES = [15, 30, 45, 60] as const;

/** Largest view we'll plan inside — beyond this Overpass loads get slow and loops meaningless. */
export const MAX_PLAN_RADIUS_M = 3000;

interface Area {
  center: LatLon;
  radiusM: number;
}

interface State {
  start: Place;
  radiusM: number;
  source: DataSource;
  profileId: ProfileId;
  timePreset: TimePreset;
  dogParks: boolean;

  status: 'idle' | 'loading' | 'ready' | 'error';
  progress: Progress | null;
  error: string | null;
  heatmap: HeatmapPayload | null;
  loadedArea: Area | null;
  selected: EdgeDetail | null;
  selectedId: number | null;
  sheetOpen: boolean;

  // Walk planning
  minutes: number;
  pace: PaceId;
  endMode: 'loop' | 'elsewhere';
  endPoint: Place | null;
  pickingEnd: boolean;
  planning: boolean;
  planMessage: string | null;
  routes: Route[];
  routeIndex: number;
  /** Registered by the map: current view as [south, west, north, east]. */
  getViewBounds: (() => Bounds) | null;
  /** Registered by the map: move the camera. */
  flyTo: ((p: LatLon, zoom?: number) => void) | null;
  /** Live GPS position while the app is open (null until permission is granted). */
  me: LatLon | null;
  /** Circle covering the current map view; null when zoomed out too far to plan. */
  viewArea: Area | null;
  viewTooBig: boolean;
  locating: boolean;
  /** 'gps' = walks start where you are; 'pin' = from a chosen address or dropped pin. */
  startMode: 'gps' | 'pin';
  /** Pin dropped by long-press / right-click, with its looked-up address. */
  pin: (LatLon & { address: string | null; resolving: boolean }) | null;
  /** In-app navigation along the selected route. */
  nav: { alongM: number; offM: number; arrived: boolean } | null;

  setStart(p: Place): void;
  setRadius(m: number): void;
  setSource(s: DataSource): void;
  setProfile(id: ProfileId): void;
  setTime(t: TimePreset): void;
  setDogParks(on: boolean): void;
  load(area?: Area): void;
  inspect(edgeId: number | null): void;
  setSheetOpen(open: boolean): void;

  setMinutes(m: number): void;
  setPace(p: PaceId): void;
  setEndMode(m: 'loop' | 'elsewhere'): void;
  setEndPoint(p: Place | null): void;
  startPicking(): void;
  onViewChanged(b: Bounds): void;
  locateMe(): Promise<void>;
  goTo(p: Place): void;
  dropPin(p: LatLon): void;
  clearPin(): void;
  pinAsStart(): void;
  pinAsFinish(): void;
  startNav(): void;
  stopNav(): void;
  optimize(): Promise<void>;
  selectRoute(i: number): void;
  clearRoutes(): void;
}

function initialFromUrl(): Pick<State, 'start' | 'radiusM' | 'source'> {
  const params = new URLSearchParams(location.search);
  const fx = params.get('fixture');
  const meta = fx ? FIXTURES.find((f) => f.name === fx) : undefined;
  if (meta) return { start: { ...meta.center, label: meta.label }, radiusM: meta.radiusM, source: { kind: 'fixture', name: meta.name } };
  const lat = Number(params.get('lat'));
  const lon = Number(params.get('lon'));
  const r = Number(params.get('r'));
  const start =
    Number.isFinite(lat) && Number.isFinite(lon) && params.has('lat')
      ? { lat, lon, label: params.get('label') ?? 'Pinned start' }
      : { ...HOME_FIXTURE.approx, label: HOME_FIXTURE.label };
  return { start, radiusM: r > 0 ? r : 1609, source: { kind: 'live' } };
}

function currentPosition(timeoutMs = 8000): Promise<LatLon | null> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) return resolve(null);
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 60_000 },
    );
  });
}

/** Circle that covers the view's corners and the given points. */
function areaCovering(b: Bounds, pts: LatLon[]): Area {
  const center = { lat: (b[0] + b[2]) / 2, lon: (b[1] + b[3]) / 2 };
  const corners = [
    { lat: b[0], lon: b[1] },
    { lat: b[2], lon: b[3] },
    ...pts,
  ];
  return { center, radiusM: Math.max(...corners.map((c) => haversineM(center, c))) };
}

function covers(outer: Area, inner: Area): boolean {
  return haversineM(outer.center, inner.center) + inner.radiusM <= outer.radiusM + 50;
}

const worker = new RoutingWorker();
let loadRequest = -1;
let inspectRequest = -1;
let planRequest = -1;
/** A plan waiting for streets to finish loading, or to re-run after a rescore. */
let pendingPlan: PlanRequest | null = null;
let lastPlan: PlanRequest | null = null;

/** Rough position from the network when GPS is off or denied (city-level accuracy). */
async function ipPosition(): Promise<LatLon | null> {
  try {
    const r = await fetch('https://get.geojs.io/v1/ip/geo.json');
    const j = (await r.json()) as { latitude?: string; longitude?: string };
    const lat = Number(j.latitude), lon = Number(j.longitude);
    return Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null;
  } catch {
    return null;
  }
}

let watchId: number | null = null;
let navCum: number[] = [];
let wakeLock: { release(): Promise<void> } | null = null;

/** Keep the screen on while navigating (best effort; not every WebView supports it). */
async function requestWakeLock() {
  try {
    const wl = (navigator as unknown as { wakeLock?: { request(t: 'screen'): Promise<{ release(): Promise<void> }> } }).wakeLock;
    wakeLock = (await wl?.request('screen')) ?? null;
  } catch {
    wakeLock = null;
  }
}

/** Continuous GPS; feeds the "you" dot and navigation progress. */
function ensureWatch() {
  if (watchId !== null || !('geolocation' in navigator)) return;
  watchId = navigator.geolocation.watchPosition(
    (p) => onPosition({ lat: p.coords.latitude, lon: p.coords.longitude }),
    () => {},
    { enableHighAccuracy: true, maximumAge: 3000 },
  );
}

function onPosition(me: LatLon) {
  const s = useStore.getState();
  if (!s.nav) return useStore.setState({ me });
  const r = s.routes[s.routeIndex];
  if (!r) return useStore.setState({ me });
  const p = project(r.coords, navCum, me, s.nav.alongM);
  // Never jump backwards more than a little (GPS jitter), unless clearly elsewhere on the route.
  const alongM = p.alongM < s.nav.alongM - 30 && p.offM < 20 ? p.alongM : Math.max(p.alongM, s.nav.alongM - 5);
  const arrived = s.nav.arrived || (r.lengthM - alongM < 25 && p.offM < 30);
  useStore.setState({ me, nav: { alongM, offM: p.offM, arrived } });
}
let viewTimer: ReturnType<typeof setTimeout> | undefined;

export const useStore = create<State>((set, get) => {
  const sendPlan = (plan: PlanRequest) => {
    lastPlan = plan;
    if (import.meta.env.DEV) console.debug('plan', JSON.stringify(plan));
    set({ planning: true, planMessage: null });
    planRequest = worker.send({ type: 'plan', plan });
  };

  worker.onMessage((msg) => {
    if (msg.type === 'progress') {
      if (msg.requestId === loadRequest || msg.requestId === planRequest) set({ progress: msg });
    } else if (msg.type === 'heatmap') {
      set({ heatmap: msg.payload, status: 'ready', progress: null, error: null });
      const id = get().selectedId;
      if (id !== null) get().inspect(id); // refresh the inspector under the new profile/time
      if (pendingPlan) {
        const p = pendingPlan;
        pendingPlan = null;
        sendPlan(p);
      }
    } else if (msg.type === 'detail') {
      if (msg.requestId === inspectRequest) set({ selected: msg.detail });
    } else if (msg.type === 'routes') {
      if (msg.requestId !== planRequest) return;
      set({
        planning: false,
        progress: null,
        routes: msg.routes,
        routeIndex: 0,
        planMessage: msg.message ?? null,
        selected: null,
        selectedId: null,
        sheetOpen: true,
      });
    } else if (msg.type === 'error') {
      pendingPlan = null;
      set({ status: get().heatmap ? 'ready' : 'error', error: msg.message, progress: null, planning: false });
    }
  });

  const rescore = () => {
    const s = get();
    if (!s.heatmap) return;
    // Routes depend on the profile and time too — re-plan once the new scores land.
    if (s.routes.length && lastPlan) pendingPlan = lastPlan;
    worker.send({ type: 'rescore', profileId: s.profileId, ctx: contextFor(s.timePreset, s.dogParks) });
  };

  return {
    ...initialFromUrl(),
    profileId: 'everyday',
    timePreset: 'now',
    dogParks: false,
    status: 'idle',
    progress: null,
    error: null,
    heatmap: null,
    loadedArea: null,
    selected: null,
    selectedId: null,
    // Start with the map in view: frame your area, then Optimize.
    sheetOpen: false,

    minutes: 30,
    pace: 'easy',
    endMode: 'loop',
    endPoint: null,
    pickingEnd: false,
    planning: false,
    planMessage: null,
    routes: [],
    routeIndex: 0,
    getViewBounds: null,
    flyTo: null,
    me: null,
    viewArea: null,
    viewTooBig: false,
    locating: false,
    startMode: 'gps',
    pin: null,
    nav: null,

    setStart: (start) => set({ start }),
    setRadius: (radiusM) => set({ radiusM }),
    setSource: (source) => {
      if (source.kind === 'fixture') {
        const meta = FIXTURES.find((f) => f.name === source.name);
        if (meta) {
          set({ start: { ...meta.center, label: meta.label }, radiusM: meta.radiusM });
          get().flyTo?.(meta.center, 14.5);
        }
      }
      set({ source, loadedArea: null });
    },
    setProfile: (profileId) => {
      set({ profileId });
      rescore();
    },
    setTime: (timePreset) => {
      set({ timePreset });
      rescore();
    },
    setDogParks: (dogParks) => {
      set({ dogParks });
      rescore();
    },
    load: (area) => {
      const s = get();
      const a = area ?? { center: { lat: s.start.lat, lon: s.start.lon }, radiusM: s.radiusM };
      set({ status: 'loading', error: null, selected: null, selectedId: null, progress: null, loadedArea: a });
      loadRequest = worker.send({
        type: 'load',
        center: a.center,
        radiusM: a.radiusM,
        source: s.source,
        profileId: s.profileId,
        ctx: contextFor(s.timePreset, s.dogParks),
      });
    },
    inspect: (edgeId) => {
      set({ selectedId: edgeId, ...(edgeId === null ? { selected: null } : {}) });
      if (edgeId !== null) inspectRequest = worker.send({ type: 'inspect', edgeId });
    },
    setSheetOpen: (sheetOpen) => set({ sheetOpen }),

    setMinutes: (minutes) => set({ minutes }),
    setPace: (pace) => set({ pace }),
    setEndMode: (endMode) => {
      set({ endMode, ...(endMode === 'loop' ? { endPoint: null, pickingEnd: false } : {}) });
      // Choosing "somewhere else" goes straight to picking the finish.
      if (endMode === 'elsewhere' && !get().endPoint) get().startPicking();
    },
    startPicking: () => set({ pickingEnd: true, sheetOpen: false, selected: null, selectedId: null, planMessage: null }),

    onViewChanged: (b) => {
      const area = areaCovering(b, []);
      const tooBig = area.radiusM > MAX_PLAN_RADIUS_M;
      set({ viewArea: tooBig ? null : area, viewTooBig: tooBig });
      const s = get();
      // Street scores follow the view (live data only; fixtures are a fixed area).
      if (tooBig || s.source.kind !== 'live' || s.routes.length || s.status === 'loading') return;
      if (s.loadedArea && covers(s.loadedArea, area)) return;
      clearTimeout(viewTimer);
      viewTimer = setTimeout(() => {
        const now = get();
        if (now.status === 'loading' || now.routes.length || !now.viewArea) return;
        // Load a bit beyond the view so small pans don't refetch.
        now.load({ center: now.viewArea.center, radiusM: Math.max(600, now.viewArea.radiusM * 1.3) });
      }, 700);
    },

    locateMe: async () => {
      set({ locating: true, planMessage: null });
      let here = await currentPosition();
      let label = 'My location';
      if (here) ensureWatch();
      if (!here) {
        here = await ipPosition();
        label = 'Approximate location';
        if (here) set({ planMessage: "GPS unavailable — using your network's approximate location. Allow location access for accuracy." });
      }
      set({ locating: false });
      if (!here) {
        set({ planMessage: 'Could not find your location. Search an address instead.' });
        return;
      }
      if (label === 'My location') set({ me: here });
      get().goTo({ ...here, label });
      set({ startMode: 'gps' });
    },

    dropPin: (p) => {
      set({ pin: { ...p, address: null, resolving: true }, selected: null, selectedId: null });
      void reverseGeocode(p).then((address) => {
        const cur = get().pin;
        if (cur && cur.lat === p.lat && cur.lon === p.lon) set({ pin: { ...cur, address, resolving: false } });
      });
    },
    clearPin: () => set({ pin: null }),
    pinAsStart: () => {
      const pin = get().pin;
      if (!pin) return;
      // An explicit start overrides live GPS for planning until "locate me" is used again.
      set({ start: { lat: pin.lat, lon: pin.lon, label: pin.address ?? 'Dropped pin' }, startMode: 'pin', pin: null, planMessage: 'Walks will start from the pin. Tap the locate button to go back to your GPS position.' });
    },
    pinAsFinish: () => {
      const pin = get().pin;
      if (!pin) return;
      set({ endMode: 'elsewhere', pin: null });
      get().setEndPoint({ lat: pin.lat, lon: pin.lon, label: pin.address ?? 'Dropped pin' });
    },

    startNav: () => {
      const s = get();
      const r = s.routes[s.routeIndex];
      if (!r) return;
      navCum = cumulative(r.coords);
      set({ nav: { alongM: 0, offM: 0, arrived: false }, sheetOpen: false, selected: null, selectedId: null, pin: null });
      ensureWatch();
      void requestWakeLock();
    },
    stopNav: () => {
      set({ nav: null, sheetOpen: true });
      void wakeLock?.release().catch(() => {});
      wakeLock = null;
    },

    goTo: (p) => {
      const s = get();
      if (s.source.kind !== 'live') set({ source: { kind: 'live' }, loadedArea: null });
      set({ start: p, startMode: 'pin' });
      s.flyTo?.(p, 15.5);
    },

    setEndPoint: (endPoint) => {
      set({ endPoint, pickingEnd: false });
      if (endPoint) void get().optimize();
    },

    optimize: async () => {
      const s = get();
      if (s.endMode === 'elsewhere' && !s.endPoint) {
        get().startPicking();
        return;
      }
      set({ planning: true, planMessage: 'Finding you…', error: null });

      // The walker is the start. Fall back to the start pin if location is unavailable.
      let start: Place = s.start;
      let located = false;
      if (s.startMode === 'pin' || s.source.kind !== 'live') {
        // explicit start: keep s.start
      } else if (s.me) {
        start = { ...s.me, label: 'My location' };
        located = true;
      } else {
        const here = await currentPosition();
        if (here) {
          start = { ...here, label: 'My location' };
          located = true;
        }
      }
      if (located) set({ start });

      const bounds = get().getViewBounds?.() ?? null;
      const pts = [start, ...(s.endPoint ? [s.endPoint] : [])];
      const area = bounds ? areaCovering(bounds, pts) : { center: start, radiusM: s.radiusM };
      if (area.radiusM > MAX_PLAN_RADIUS_M) {
        set({ planning: false, planMessage: 'That view is too big to plan in — zoom in to the area you want to walk.' });
        return;
      }

      const plan: PlanRequest = {
        start,
        end: s.endMode === 'elsewhere' ? s.endPoint : null,
        targetM: (s.minutes / 60) * PACES[s.pace].mph * 1609.344,
        paceMph: PACES[s.pace].mph,
        tolerance: 0.15,
        bounds,
      };
      set({ planMessage: located || s.source.kind !== 'live' || s.startMode === 'pin' ? null : 'Location unavailable — starting from the pin.' });

      const loaded = get().loadedArea;
      const haveStreets = get().heatmap && (s.source.kind === 'fixture' || (loaded && covers(loaded, area)));
      if (haveStreets) sendPlan(plan);
      else {
        pendingPlan = plan;
        get().load({ center: area.center, radiusM: Math.max(area.radiusM, 400) });
      }
    },
    selectRoute: (routeIndex) => set({ routeIndex }),
    clearRoutes: () => {
      lastPlan = null;
      if (get().nav) get().stopNav();
      set({ routes: [], routeIndex: 0, planMessage: null, endPoint: null, pickingEnd: false });
    },
  };
});

// Dev-only handle for debugging in the browser console.
if (import.meta.env.DEV) (globalThis as unknown as { sniffari: typeof useStore }).sniffari = useStore;
