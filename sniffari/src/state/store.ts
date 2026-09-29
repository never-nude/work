import { create } from 'zustand';
import type { EdgeDetail, DataSource, HeatmapPayload, Stage } from '../routing/protocol';
import type { LatLon, ProfileId, Route, ScoringContext } from '../types';
import type { Bounds, PlanRequest } from '../routing/loopGenerator';
import { haversineM } from '../graph/geo';
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

export const useStore = create<State>((set, get) => {
  const sendPlan = (plan: PlanRequest) => {
    lastPlan = plan;
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

    setStart: (start) => set({ start }),
    setRadius: (radiusM) => set({ radiusM }),
    setSource: (source) => {
      if (source.kind === 'fixture') {
        const meta = FIXTURES.find((f) => f.name === source.name);
        if (meta) set({ start: { ...meta.center, label: meta.label }, radiusM: meta.radiusM });
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
    setEndMode: (endMode) => set({ endMode, ...(endMode === 'loop' ? { endPoint: null, pickingEnd: false } : {}) }),
    setEndPoint: (endPoint) => {
      set({ endPoint, pickingEnd: false });
      if (endPoint) void get().optimize();
    },

    optimize: async () => {
      const s = get();
      if (s.endMode === 'elsewhere' && !s.endPoint) {
        set({ pickingEnd: true, planMessage: 'Tap the map where you want to finish.', sheetOpen: false, selected: null, selectedId: null });
        return;
      }
      set({ planning: true, planMessage: 'Finding you…', error: null });

      // The walker is the start. Fall back to the start pin if location is unavailable.
      let start: Place = s.start;
      let located = false;
      if (s.source.kind === 'live') {
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
      set({ planMessage: located || s.source.kind !== 'live' ? null : 'Location unavailable — starting from the pin.' });

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
      set({ routes: [], routeIndex: 0, planMessage: null, endPoint: null, pickingEnd: false });
    },
  };
});
