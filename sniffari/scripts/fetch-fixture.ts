// Pulls the real-world test fixture (CLAUDE.md: AVE Hamilton Green, White Plains)
// from Nominatim + Overpass and saves it under fixtures/. Run once, locally:
//
//   npm run fixture:fetch                       # default 1 mi radius
//   npm run fixture:fetch -- --radius 2414      # 1.5 mi
//   npm run fixture:fetch -- --name sterling --address "10 Sterling Ave, White Plains, NY"
//
// --name becomes fixtures/<name>.* and the app's ?fixture=<name>.
//
// Polite by design: one geocode request, one Overpass request, ~20 elevation tiles, descriptive User-Agent.
import { mkdirSync, writeFileSync } from 'node:fs';
import { bboxAround, buildQuery, fetchOverpass } from '../src/data/overpass';
import { terrariumUrl, tilesForElevation } from '../src/data/elevation';

const arg = (flag: string): string | undefined => {
  const i = process.argv.indexOf(flag);
  return i > 0 ? process.argv[i + 1] : undefined;
};

const NAME = arg('--name') ?? 'white-plains';
const QUERY = arg('--address') ?? '25 Cottage Place, White Plains, NY 10601';
const LABEL = arg('--label') ?? (arg('--address') ? QUERY.split(',')[0]! : 'AVE Hamilton Green, 25 Cottage Pl');
if (!/^[a-z0-9-]+$/.test(NAME)) throw new Error('--name must be lowercase letters, digits and dashes');
const UA = 'Sniffari/0.1 (dog-walk route planner; dev fixture script; https://github.com/never-nude/work)';
const MARGIN_M = 400;

const radiusM = Number(arg('--radius') ?? 1609);

async function main() {
  console.log(`Geocoding "${QUERY}"…`);
  const url = `https://nominatim.openstreetmap.org/search?${new URLSearchParams({ q: QUERY, format: 'jsonv2', limit: '1' })}`;
  const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
  if (!res.ok) throw new Error(`Nominatim ${res.status}`);
  const rows = (await res.json()) as { lat: string; lon: string; display_name: string }[];
  const hit = rows[0];
  if (!hit) throw new Error('Address not found');
  const center = { lat: +hit.lat, lon: +hit.lon };
  console.log(`  → ${hit.display_name} (${center.lat}, ${center.lon})`);
  writeFileSync(`fixtures/${NAME}.geocode.json`, JSON.stringify(rows, null, 2) + '\n');

  const bbox = bboxAround(center, radiusM + MARGIN_M);
  console.log(`Fetching Overpass for ${Math.round(radiusM)} m radius (+${MARGIN_M} m margin)…`);
  const t0 = Date.now();
  const data = await fetchOverpass(buildQuery(bbox, 180), {
    fetchImpl: (input, init) => fetch(input, { ...init, headers: { 'User-Agent': UA } }),
  });
  const json = JSON.stringify({ elements: data.elements });
  writeFileSync(`fixtures/${NAME}.overpass.json`, json + '\n');
  writeFileSync(
    `fixtures/${NAME}.meta.json`,
    JSON.stringify({ name: NAME, label: LABEL, center, radiusM, fetchedAt: new Date().toISOString(), bbox }, null, 2) + '\n',
  );
  console.log(`  → ${data.elements.length.toLocaleString()} elements, ${(json.length / 1e6).toFixed(1)} MB in ${((Date.now() - t0) / 1000).toFixed(1)} s`);

  const tiles = tilesForElevation(bbox);
  console.log(`Fetching ${tiles.length} elevation tiles…`);
  const dir = `fixtures/${NAME}.elevation`;
  mkdirSync(dir, { recursive: true });
  for (const t of tiles) {
    const r = await fetch(terrariumUrl(t.z, t.x, t.y), { headers: { 'User-Agent': UA } });
    if (!r.ok) throw new Error(`Elevation tile ${t.z}/${t.x}/${t.y}: ${r.status}`);
    writeFileSync(`${dir}/${t.z}-${t.x}-${t.y}.png`, Buffer.from(await r.arrayBuffer()));
  }
  console.log(`Saved fixtures/${NAME}.{overpass,meta,geocode}.json + ${dir}/ — open the app with ?fixture=${NAME}`);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
