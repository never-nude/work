# Sniffari — Phase 0 plan (and what Phase 1 actually built)

Phase 0 asked for a plan only. The session was kicked off with "let's vibecode this", so Phase 1
(data + graph + heatmap) was built as well — the plan below describes the code that exists, and
every decision that belongs to Mike is listed in §6 as a proposal, not a done deal.

## 1. File tree

```
sniffari/
  CLAUDE.md, KICKOFF.md          project guide + original kickoff prompt
  docs/SPEC.md, docs/PLAN.md
  fixtures/
    synthetic.overpass.json      hand-built test neighbourhood (scripts/make-synthetic-fixture.mjs)
    synthetic.meta.json
    white-plains.*.json          created locally by `npm run fixture:fetch` (not yet present)
    ground-truth.json            Mike's walked ratings (empty)
  scripts/
    make-synthetic-fixture.mjs   regenerates the synthetic fixture
    fetch-fixture.ts             geocode + Overpass → fixtures/white-plains.*
    calibrate.ts                 model vs ground-truth table + Spearman ρ
  public/brand/                  app-icon.png / logo.png go here
  src/
    types.ts                     all domain types
    data/      overpass.ts  cache.ts  geocode.ts            (weather.ts arrives in Phase 4)
    graph/     geo.ts  osmTags.ts  spatialIndex.ts  buildGraph.ts  edgeFeatures.ts
    scoring/   factors/{sidewalk,quiet,grass,shade,crossings,crowds,surface,lighting,amenities,rules,hazards}.ts
               profiles.ts  scoreEdge.ts                    (scoreRoute.ts arrives in Phase 2)
    routing/   protocol.ts  pipeline.ts  worker.ts          (astar/loopGenerator/destinations: Phase 2–3)
    state/     store.ts  workerClient.ts  fixtures.ts
    ui/        App.tsx  styles.css  map/  panels/  components/
```

## 2. Types (src/types.ts)

- **OSM input**: `OverpassNode | OverpassWay | OverpassRelation`, `OverpassResponse`.
- **Graph**: `GraphNode { id, osmId, lat, lon, x, y, tags?, crossing: CrossingKind, edgeIds }`,
  `Edge { id, wayId, from, to, coords: [lon,lat][], lengthM, name, tags, features }`,
  `Graph { nodes, edges, center }`. Node/edge ids are dense array indices (fast in the worker).
  `x, y` are local metres from an equirectangular projection around the start.
- **EdgeFeatures**: everything a factor may read, precomputed once — road class, parsed sidewalk
  state, maxspeed (mph), lanes, surface, lit, access/foot/dog, plus spatial measures:
  `distMajorRoadM`, `distRailM`, `grassFraction`, `nearGrassM`, `treesPer100m`, `canopyFraction`,
  `commercialPer100m`, `distStationM`, `busStops`, `amenities{…}`. Factors never see raw OSM.
- **Scoring**: `FactorResult { score ∈ [0,1], reason }`, `EdgeFactor = (features, ctx) => FactorResult`,
  `ScoringContext { hour, isDark, weather? }`, `Profile { id, name, blurb, weights, amenityBonus, shortWalk? }`,
  `EdgeScore { q, excluded, factors, amenities }`.
- **Phase 2+ (declared, unused yet)**: `WalkRequest`, `Route`, `Destination`, `PointOfInterest`, `RouteWarning`.

## 3. Module interfaces

| Module | Signature | Does |
|---|---|---|
| data/overpass | `bboxAround(center, r)`, `tilesForBBox(bbox)`, `buildQuery(bbox)`, `fetchOverpass(q, opts)` | fixed 0.02° tile grid, one query per tile, endpoint fallback + 429 backoff |
| data/cache | `new TTLCache(store?, ttl?)`, `.getOrFetch(key, fn)` | IndexedDB (idb-keyval) with 7-day TTL; memory store for tests |
| data/geocode | `geocode(q)` | Nominatim (throttled 1/s) → Photon fallback |
| graph/buildGraph | `mergeResponses(rs)`, `buildGraph(osm, center, {radiusM})` | dedupe tiles; split ways at shared nodes; classify major-road crossings |
| graph/edgeFeatures | `buildFeatureLayers(osm, proj)`, `computeEdgeFeatures(edge, layers, proj)`, `attachFeatures(base, osm)` | Flatbush layers; sample each edge every 10 m and measure |
| graph/spatialIndex | `PointIndex`, `SegmentIndex`, `AreaIndex` | radius / nearest / point-in-area queries in metres |
| scoring/factors/* | `(f, ctx) => FactorResult` | one factor per file; `crossingsFactor(kinds, lengthM)` is route-level; `exclusionReason(f)` is the single hard-exclusion rule |
| scoring/profiles | `PROFILES`, `PROFILE_ORDER` | SPEC §5 presets |
| scoring/scoreEdge | `effectiveEdgeWeights(profile, ctx, overrides?)`, `scoreEdge(f, w, ctx)`, `edgeCost(len, s, α)` | weighted mean q; cost = len·(1+α(1−q)) |
| routing/pipeline | `buildScoredGraphInputs`, `scoreAll`, `toHeatmap`, `edgeDetail` | pure pipeline (shared by worker, tests, calibrate script) |
| routing/worker | message handler | fetch/cache → graph → features → scores, in a Web Worker |

## 4. Overpass query and size

`buildQuery(bbox)` in `src/data/overpass.ts`. Per tile, one request with five output blocks:

1. `way["highway"~walkable|major|construction](bbox)` → `out body`, then `node(w.roads); out body`
   (road nodes *with* tags, so `crossing=*` and `traffic_signals` come along).
2. grass/park/wood/tree_row/rail ways → `out geom` (inline geometry; no extra node fetch).
3. the same areas as multipolygon relations → `out geom`.
4. point POIs: trees, shops, food/drink, bins, bag dispensers, water, benches, bus stops, stations, `dog=yes`.
5. shops/restaurants/stations mapped as buildings → `out tags center`.

The bbox is on each statement (not the global `[bbox:]` setting) so roads keep all their nodes past
the tile edge.

**Size, estimated (not measured — Overpass is blocked from this environment):** a 1.5-mile walk
radius + 400 m margin is ~5.6 × 5.6 km ≈ 31 km², i.e. 12–16 tiles. Dense downtown + suburban
White Plains is plausibly 1–3 MB of JSON per tile, so **~10–30 MB raw (~2–5 MB over the wire
gzipped)** on first load, then cached. `npm run fixture:fetch` prints the real number — please
paste it back so we can tune.

## 5. Web Worker boundary (src/routing/protocol.ts)

- **In**: `load { center, radiusM, source: live|fixture, profileId, ctx }`,
  `rescore { profileId, ctx }` (no refetch/rebuild — ~ms), `inspect { edgeId }`.
- **Out**: `progress { stage: fetch|graph|features|score, done, total, message }`,
  `heatmap { edges GeoJSON (id, q, name), crossings GeoJSON, stats }`, `detail { features, factor results, weights }`,
  `error { message }`.
- Fetching and caching happen *inside* the worker so multi-MB JSON is parsed off the main thread
  and never structured-cloned across. The graph lives in the worker; the UI only gets thin GeoJSON.
  Phase 2 adds `route { WalkRequest }` → `routes { Route[] }` on the same channel.

## 6. Pushback, open questions, and decisions I made that are yours to overrule

**Model**
1. **Weighted mean compresses the range.** Sidewalk, lighting and surface score well almost
   everywhere, so a 4-lane arterial still lands ~0.35–0.45 under "Quiet". A dog-walker would call it
   a 5/100. Suggest a veto term, e.g. `q = mean × min(1, worst/0.3)^0.5`, so one terrible factor
   can sink a street. Not implemented — calibration against ground truth should decide.
2. **Unmapped is the norm, not the edge case.** US OSM rarely tags sidewalks, lawns, street trees or
   lighting. The defaults for *unknown* (residential sidewalk 0.75, lawn baseline 0.3, "probably lit"
   0.7) matter more than the tagged logic. They're the first knobs to calibrate.
3. **"Secondary+ without sidewalk → excluded"** is applied only for an explicit `sidewalk=no`. Treating
   *unknown* as "no" would delete most of downtown.
4. **`sidewalk=separate` double-counts.** Main St and its separately-mapped sidewalks both exist in
   the graph. Phase 2 must stop routes walking down the road centreline: proposal — exclude
   secondary+ roads tagged `separate`, keep them only as crossing connectors. Needs your call.
5. **Crossings belong in the A\* cost**, not just the final route score, or the router won't avoid
   them. Proposal: node penalty = `CROSSING_PENALTY[kind] × 150 m`. Also consider tertiary crossings;
   the spec counts secondary+ only.
6. **Potty break** has no weights in the spec. Proposed: grass .40, crossings .20, quiet .20, sidewalk .20.
   Senior's weights sum to 0.85 — they're normalised, so ratios are preserved.
7. **Lighting after dark** gets weight 0.15 in every profile (spec says "weighted after sunset" without a number).
8. **Driveways** (`service=driveway|drive-through`) are excluded — not in the spec, but they're dead
   ends that clutter the heatmap and invite routes into private property.
9. **Crowd time multipliers** (rush 1.2, lunch 1.3, evening 1.4, night 0.5) are guesses; weekday vs
   weekend is ignored.

**Data / product**
10. **Ground truth needs locators.** Free-text "Oak St between A and B" can't be matched to edges
    reliably. `ground-truth.json` entries now accept optional `wayIds`, `at {lat,lon}`, `profile`,
    `hour`; the inspector's *Copy ground-truth stub* button fills them. SPEC fields are unchanged.
11. **First load is slow.** 12–16 tiles at 2 concurrent Overpass slots is 30–90 s cold. Alternative:
    one union-bbox request, split into per-tile cache entries. Worth it if the real fixture timing is bad.
12. **Turf.js is not used.** Everything needed (projection, sampling, point-segment distance,
    point-in-polygon) is ~120 lines in `graph/geo.ts` + `spatialIndex.ts`, all in metres. Add Turf
    back if you want it on principle; nothing needs it yet.
13. **Basemap**: OpenFreeMap `dark` is tried, then `fiord`, then a blank dark canvas. I could not
    verify either style URL from here (network-blocked).

**Repo / process**
14. **This lives in `never-nude/work/sniffari/`** because that was the only repo this session could
    reach. `work` is the static kushman.work Pages site — merging to `main` would publish the
    *unbuilt* dev `index.html` at kushman.work/sniffari/. Recommend a dedicated `never-nude/sniffari`
    repo (the spec's Actions → Pages deploy assumes one). Don't merge the PR until that's decided.
15. **CLAUDE.md says "never push".** This cloud container is ephemeral, so work was pushed to a
    feature branch with a draft PR (nothing to `main`). Locally, the rule stands.
