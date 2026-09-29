import { create } from 'zustand';
import type { EdgeDetail, DataSource, HeatmapPayload, Stage } from '../routing/protocol';
import type { LatLon, ProfileId, ScoringContext } from '../types';
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
  selected: EdgeDetail | null;
  selectedId: number | null;
  sheetOpen: boolean;

  setStart(p: Place): void;
  setRadius(m: number): void;
  setSource(s: DataSource): void;
  setProfile(id: ProfileId): void;
  setTime(t: TimePreset): void;
  setDogParks(on: boolean): void;
  load(): void;
  inspect(edgeId: number | null): void;
  setSheetOpen(open: boolean): void;
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

const worker = new RoutingWorker();
let loadRequest = -1;
let inspectRequest = -1;

export const useStore = create<State>((set, get) => {
  worker.onMessage((msg) => {
    if (msg.type === 'progress') {
      if (msg.requestId === loadRequest) set({ progress: msg });
    } else if (msg.type === 'heatmap') {
      set({ heatmap: msg.payload, status: 'ready', progress: null, error: null });
      const id = get().selectedId;
      if (id !== null) get().inspect(id); // refresh the inspector under the new profile/time
    } else if (msg.type === 'detail') {
      if (msg.requestId === inspectRequest) set({ selected: msg.detail });
    } else if (msg.type === 'error') {
      set({ status: 'error', error: msg.message, progress: null });
    }
  });

  const rescore = () => {
    const s = get();
    if (!s.heatmap) return;
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
    selected: null,
    selectedId: null,
    sheetOpen: true,

    setStart: (start) => set({ start }),
    setRadius: (radiusM) => set({ radiusM }),
    setSource: (source) => {
      if (source.kind === 'fixture') {
        const meta = FIXTURES.find((f) => f.name === source.name);
        if (meta) set({ start: { ...meta.center, label: meta.label }, radiusM: meta.radiusM });
      }
      set({ source });
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
    load: () => {
      const s = get();
      set({ status: 'loading', error: null, selected: null, selectedId: null, progress: null });
      loadRequest = worker.send({
        type: 'load',
        center: { lat: s.start.lat, lon: s.start.lon },
        radiusM: s.radiusM,
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
  };
});
