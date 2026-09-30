/// <reference lib="webworker" />
import type { LatLon, OverpassResponse, ScoringContext } from '../types';
import { bboxAround, buildQuery, fetchOverpass, QUERY_VERSION, tilesForBBox } from '../data/overpass';
import { TTLCache } from '../data/cache';
import {
  fetchTerrariumTile,
  makeElevationLookup,
  tilesForElevation,
  type DecodedTile,
  type ElevationAt,
} from '../data/elevation';
import { PROFILES } from '../scoring/profiles';
import type { ProfileId } from '../types';
import { buildScoredGraphInputs, edgeDetail, scoreAll, toHeatmap, type BuiltGraph } from './pipeline';
import type { DataSource, Stage, WorkerRequest, WorkerResponse } from './protocol';
import { Planner } from './loopGenerator';
import type { EdgeScore } from '../types';

declare const self: DedicatedWorkerGlobalScope;

const fixtureLoaders = import.meta.glob<OverpassResponse>('../../fixtures/*.overpass.json', { import: 'default' });
/** Terrain PNGs saved by `npm run fixture:fetch`: fixtures/<name>.elevation/<z>-<x>-<y>.png */
const fixtureElevation = import.meta.glob<string>('../../fixtures/*.elevation/*.png', { query: '?url', import: 'default' });

const cache = new TTLCache();
/** Extra data beyond the walk radius so features (grass, major roads) near the edge are seen. */
const MARGIN_M = 250;
const MAX_PARALLEL = 2; // Overpass allows ~2 concurrent slots per IP

let graph: BuiltGraph | null = null;
let current = { profileId: 'everyday' as ProfileId, ctx: { hour: 12, isDark: false } as ScoringContext };
let fetchMs = 0;
let tileStats = { total: 0, cached: 0 };
let elevationTiles = 0;
let scores: EdgeScore[] = [];
let currentRequest = -1;

const post = (msg: WorkerResponse) => self.postMessage(msg);

async function loadResponses(
  requestId: number,
  center: LatLon,
  radiusM: number,
  source: DataSource,
): Promise<OverpassResponse[]> {
  const progress = (done: number, total: number, message: string) =>
    post({ type: 'progress', requestId, stage: 'fetch', done, total, message });

  if (source.kind === 'fixture') {
    const loader = fixtureLoaders[`../../fixtures/${source.name}.overpass.json`];
    if (!loader) throw new Error(`Fixture "${source.name}" not found. Run: npm run fixture:fetch`);
    progress(0, 1, 'Loading fixture…');
    const data = await loader();
    tileStats = { total: 1, cached: 1 };
    return [data];
  }

  const tiles = tilesForBBox(bboxAround(center, radiusM + MARGIN_M));
  tileStats = { total: tiles.length, cached: 0 };
  const out: OverpassResponse[] = [];
  let done = 0;
  progress(0, tiles.length, `Fetching map data (${tiles.length} tiles)…`);
  const queue = [...tiles];
  const workers = Array.from({ length: MAX_PARALLEL }, async () => {
    while (queue.length) {
      const tile = queue.shift()!;
      const { value, hit } = await cache.getOrFetch(`overpass:v${QUERY_VERSION}:${tile.key}`, () =>
        fetchOverpass(buildQuery(tile.bbox)),
      );
      if (hit) tileStats.cached++;
      out.push(value);
      done++;
      progress(done, tiles.length, `Map data ${done}/${tiles.length}${tileStats.cached ? ` (${tileStats.cached} cached)` : ''}`);
    }
  });
  await Promise.all(workers);
  return out;
}

/** Elevation is best-effort: any failure leaves terrain "unavailable" instead of failing the load. */
async function loadElevation(center: LatLon, radiusM: number, source: DataSource): Promise<ElevationAt | undefined> {
  const tiles: DecodedTile[] = [];
  try {
    if (source.kind === 'fixture') {
      const prefix = `../../fixtures/${source.name}.elevation/`;
      for (const [path, load] of Object.entries(fixtureElevation)) {
        if (!path.startsWith(prefix)) continue;
        const [z, x, y] = path.slice(prefix.length, -4).split('-').map(Number) as [number, number, number];
        tiles.push(await fetchTerrariumTile(z, x, y, undefined, await load()));
      }
    } else {
      const want = tilesForElevation(bboxAround(center, radiusM + MARGIN_M));
      let done = 0;
      const queue = [...want];
      await Promise.all(
        Array.from({ length: 4 }, async () => {
          while (queue.length) {
            const t = queue.shift()!;
            const { value } = await cache.getOrFetch(`terrarium:${t.z}/${t.x}/${t.y}`, () => fetchTerrariumTile(t.z, t.x, t.y));
            tiles.push(value);
            done++;
            post({ type: 'progress', requestId: currentRequest, stage: 'fetch', done, total: want.length, message: `Elevation ${done}/${want.length}` });
          }
        }),
      );
    }
  } catch (e) {
    console.warn('Elevation unavailable:', e);
    tiles.length = 0;
  }
  elevationTiles = tiles.length;
  return tiles.length ? makeElevationLookup(tiles) : undefined;
}

function emitHeatmap(requestId: number, msScore: number) {
  if (!graph) return;
  const t0 = performance.now();
  scores = scoreAll(graph.edges, PROFILES[current.profileId], current.ctx);
  const payload = toHeatmap(graph, scores, {
    tiles: tileStats,
    elevationTiles,
    ms: { fetch: fetchMs, graph: graph.msGraph, features: graph.msFeatures, score: msScore || performance.now() - t0 },
  });
  post({ type: 'heatmap', requestId, payload });
}

self.onmessage = async (ev: MessageEvent<WorkerRequest>) => {
  const req = ev.data;
  try {
    if (req.type === 'load') {
      currentRequest = req.requestId;
      current = { profileId: req.profileId, ctx: req.ctx };
      const t0 = performance.now();
      const responses = await loadResponses(req.requestId, req.center, req.radiusM, req.source);
      post({ type: 'progress', requestId: req.requestId, stage: 'fetch', done: 1, total: 1, message: 'Loading elevation…' });
      const elevationAt = await loadElevation(req.center, req.radiusM, req.source);
      fetchMs = performance.now() - t0;
      const stageMsg: Record<Stage, string> = {
        fetch: '',
        graph: 'Building street graph…',
        features: 'Measuring grass, trees, traffic…',
        score: 'Scoring streets…',
        route: '',
      };
      graph = buildScoredGraphInputs(responses, req.center, req.radiusM, (stage, done, total) =>
        post({ type: 'progress', requestId: req.requestId, stage, done, total, message: stageMsg[stage] }),
        elevationAt,
      );
      post({ type: 'progress', requestId: req.requestId, stage: 'score', done: 0, total: 1, message: stageMsg.score });
      emitHeatmap(req.requestId, 0);
    } else if (req.type === 'rescore') {
      current = { profileId: req.profileId, ctx: req.ctx };
      emitHeatmap(req.requestId, 0);
    } else if (req.type === 'plan') {
      if (!graph || !scores.length) throw new Error('Load streets first');
      const planner = new Planner(graph, scores, PROFILES[current.profileId], current.ctx);
      const t0 = performance.now();
      const res = planner.plan(req.plan, (done, total) => {
        if (done % 8 === 0) post({ type: 'progress', requestId: req.requestId, stage: 'route', done, total, message: 'Trying loop shapes…' });
      });
      console.debug(`planned ${res.candidates} candidates in ${Math.round(performance.now() - t0)} ms`);
      post({ type: 'routes', requestId: req.requestId, ...res });
    } else if (req.type === 'inspect') {
      if (!graph) throw new Error('No graph loaded');
      const detail = edgeDetail(graph, req.edgeId, PROFILES[current.profileId], current.ctx);
      if (!detail) throw new Error(`Unknown edge ${req.edgeId}`);
      post({ type: 'detail', requestId: req.requestId, detail });
    }
  } catch (e) {
    post({ type: 'error', requestId: req.requestId, message: e instanceof Error ? e.message : String(e) });
  }
};
