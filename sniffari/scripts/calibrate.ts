// Compares the model's edge quality with Mike's walked ratings.
//
//   npm run calibrate                     # uses fixtures/white-plains.*
//   npm run calibrate -- --fixture synthetic
//
// fixtures/ground-truth.json entries (SPEC §8 plus optional locators):
//   { "street": "Oak Ave between A and B", "rating": 1-5, "notes": "…",
//     "wayIds": [123], "at": { "lat": …, "lon": … }, "profile": "quiet", "hour": 18 }
// Entries need wayIds or at (the inspector's "Copy ground-truth stub" fills both).
import { readFileSync, existsSync } from 'node:fs';
import type { Edge, LatLon, OverpassResponse, ProfileId } from '../src/types';
import { buildScoredGraphInputs } from '../src/routing/pipeline';
import { effectiveEdgeWeights, scoreEdge } from '../src/scoring/scoreEdge';
import { PROFILES } from '../src/scoring/profiles';
import { haversineM } from '../src/graph/geo';

interface Truth {
  street: string;
  rating: number | null;
  notes?: string;
  wayIds?: number[];
  at?: LatLon;
  profile?: ProfileId;
  hour?: number;
}

const fx = process.argv.includes('--fixture') ? process.argv[process.argv.indexOf('--fixture') + 1]! : 'white-plains';
const metaPath = `fixtures/${fx}.meta.json`;
if (!existsSync(metaPath)) {
  console.error(`No ${metaPath}. Run: npm run fixture:fetch`);
  process.exit(1);
}
const meta = JSON.parse(readFileSync(metaPath, 'utf8')) as { center: LatLon; radiusM: number };
const data = JSON.parse(readFileSync(`fixtures/${fx}.overpass.json`, 'utf8')) as OverpassResponse;
const truth = (JSON.parse(readFileSync('fixtures/ground-truth.json', 'utf8')) as Truth[]).filter(
  (t) => typeof t.rating === 'number',
);

if (truth.length === 0) {
  console.log('fixtures/ground-truth.json has no rated entries yet.');
  console.log('Walk some streets, tap them in the app, "Copy ground-truth stub", paste into the file and set "rating" 1–5.');
  process.exit(0);
}

const g = buildScoredGraphInputs([data], meta.center, meta.radiusM + 400);

function edgesFor(t: Truth): Edge[] {
  if (t.wayIds?.length) {
    const hits = g.edges.filter((e) => t.wayIds!.includes(e.wayId));
    if (hits.length) return hits;
  }
  if (t.at) {
    let best: Edge | null = null;
    let bestD = Infinity;
    for (const e of g.edges) {
      for (const [lon, lat] of e.coords) {
        const d = haversineM(t.at, { lat, lon });
        if (d < bestD) {
          bestD = d;
          best = e;
        }
      }
    }
    if (best && bestD < 40) return [best];
  }
  return [];
}

function ranks(xs: number[]): number[] {
  const idx = xs.map((v, i) => [v, i] as const).sort((a, b) => a[0] - b[0]);
  const r = new Array<number>(xs.length);
  for (let i = 0; i < idx.length; ) {
    let j = i;
    while (j + 1 < idx.length && idx[j + 1]![0] === idx[i]![0]) j++;
    for (let k = i; k <= j; k++) r[idx[k]![1]] = (i + j) / 2 + 1;
    i = j + 1;
  }
  return r;
}

function pearson(a: number[], b: number[]): number {
  const n = a.length;
  const ma = a.reduce((s, v) => s + v, 0) / n;
  const mb = b.reduce((s, v) => s + v, 0) / n;
  let num = 0, da = 0, db = 0;
  for (let i = 0; i < n; i++) {
    num += (a[i]! - ma) * (b[i]! - mb);
    da += (a[i]! - ma) ** 2;
    db += (b[i]! - mb) ** 2;
  }
  return da && db ? num / Math.sqrt(da * db) : NaN;
}

const rows: { street: string; rating: number; model: number; expected: number }[] = [];
for (const t of truth) {
  const edges = edgesFor(t);
  if (!edges.length) {
    console.warn(`  ? couldn't locate "${t.street}" (add wayIds or at)`);
    continue;
  }
  const ctx = { hour: t.hour ?? 12, isDark: (t.hour ?? 12) >= 19 || (t.hour ?? 12) < 7 };
  const w = effectiveEdgeWeights(PROFILES[t.profile ?? 'quiet'], ctx);
  let len = 0, sum = 0;
  for (const e of edges) {
    const s = scoreEdge(e.features, w, ctx);
    sum += s.q * e.lengthM;
    len += e.lengthM;
  }
  rows.push({ street: t.street, rating: t.rating!, model: Math.round((sum / len) * 100), expected: Math.round(((t.rating! - 1) / 4) * 100) });
}

rows.sort((a, b) => Math.abs(b.model - b.expected) - Math.abs(a.model - a.expected));
console.log('\nstreet'.padEnd(46) + 'rating  model  expected  diff');
for (const r of rows) {
  const diff = r.model - r.expected;
  console.log(
    `${r.street.slice(0, 44).padEnd(45)} ${String(r.rating).padStart(4)}  ${String(r.model).padStart(5)}  ${String(r.expected).padStart(8)}  ${(diff > 0 ? '+' : '') + diff}`,
  );
}
if (rows.length >= 3) {
  const rho = pearson(ranks(rows.map((r) => r.rating)), ranks(rows.map((r) => r.model)));
  console.log(`\nSpearman ρ = ${rho.toFixed(2)} over ${rows.length} streets (1.0 = model ranks streets exactly like you do)`);
}
