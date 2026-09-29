# Sniffari — Product Spec

## 1. The problem

Someone moves somewhere new with a dog and has no idea where to walk. Map apps optimize for getting somewhere fast; dog walks optimize for the opposite — quiet, grass to sniff, sidewalks, few scary crossings, shade in summer, a bin for the bag, maybe a dog park as a destination. Sniffari answers: *"Given where I am, how long I've got, and what my dog needs, what's the best walk right now?"*

It should work anywhere OpenStreetMap has decent coverage — dense downtowns, suburbs, and the mixed zones in between.

## 2. Inputs

| Input | Details |
|---|---|
| Start | Current location (default) or typed address |
| Walk mode | **Loop** (return home, default) · **Out-and-back** to a destination · **One-way** to a destination |
| Target | Duration (minutes) **or** distance (mi/km). If duration is given, distance = duration × pace |
| Pace | Presets: **Sniff walk** 1.5 mph · **Easy stroll** 2.2 mph · **Brisk** 3.0 mph · custom |
| Tolerance | ±10% of target distance (adjustable) |
| Departure time | Now (default) or scheduled — drives time-of-day and weather weighting |
| Dog profile | Preset weight profile (§5), with sliders to fine-tune |

## 3. Outputs

- **Top 3 routes** on the map, visually distinct (pairwise edge overlap < 40%), each with:
  - Score 0–100 and a per-factor breakdown (small bars)
  - One-line "why" ("Mostly quiet residential streets, two grass stretches, one signalized crossing of Main St")
  - Actual distance and estimated time at chosen pace
  - Points of interest along the way: grass patches, water, waste bins, benches, dog-friendly businesses
  - Warnings: hot pavement, unsignalized busy crossing, unlit segment after dark, stretch without sidewalk
- **Best destinations** within range (dog parks, dog-allowed parks, big grass areas, dog-friendly patios, pet stores), ranked by destination quality × route quality × fit
- **Debug layer** (dev toggle): every street colored by edge quality — the main tool for calibrating the model
- Later: GPX export, shareable link, "Dog Walk Score" for any address

## 4. Quality factors

Each factor yields a subscore in [0,1] per edge (or per route for route-level factors) plus a reason string.

| # | Factor | v1 derivation (OSM tags / sources) | Later upgrade |
|---|---|---|---|
| 1 | **Sidewalk** | `sidewalk=both/left/right/separate`, `footway=sidewalk`, `highway=footway/pedestrian/path/living_street`. Low-speed residential w/o sidewalk ≈ 0.5. Secondary+ without sidewalk → excluded | Sidewalk-condition reports |
| 2 | **Quiet / traffic** | Road class (living_street/residential 1.0 → tertiary 0.6 → secondary 0.3 → primary 0.1), `maxspeed`, `lanes`; distance buffer from nearest major road and from `railway=rail` | US DOT BTS National Transportation Noise Map raster |
| 3 | **Grass / sniff access** | Bordering *or near* (≤400 m, decaying) `landuse=grass`, `leisure=park`, `natural=grassland/scrub`, `landuse=meadow`, `leisure=garden` (public) — somewhere to do business. Dog parks neutral unless the "Count dog parks" preference is on | NDVI from Sentinel-2 or NLCD |
| 4 | **Shade** | `natural=tree`, `natural=tree_row`, `landuse=forest`, `natural=wood` nearby | NLCD Tree Canopy Cover |
| 5 | **Crossings** | Route-level: count crossings of secondary+ roads; signalized (`crossing=traffic_signals`) scored better than marked, marked better than unmarked | — |
| 6 | **Crowds / commercial density** | Density of `shop=*`, `amenity=restaurant/bar/cafe/fast_food`, bus stops, station proximity; scaled by time of day (lunch, evening, rush hour) | Foot-traffic data |
| 7 | **Surface** | `surface=*`: paved vs unpaved — unpaved/grass favored in heat, penalized after rain (Open-Meteo recent precipitation) | — |
| 8 | **Lighting** | `lit=yes/no`; only weighted after sunset | — |
| 9 | **Amenities (bonus)** | `amenity=waste_basket`, `vending=excrement_bags`, `amenity=drinking_water` (+`dog=yes`), `amenity=bench`, businesses with `dog=yes` | Crowdsourced |
| 10 | **Rules** | `dog=no` → excluded; `dog=leashed` fine; `leisure=dog_park` as destination; `access=private/no` → excluded | Municipal park-rule data |
| 11 | **Hazards** | `highway=construction`, `construction=*` → excluded | User reports |
| 12 | **Terrain** | Mean grade along each edge from Terrarium elevation tiles (AWS Open Data, keyless); flat 1.0 → 5% 0.6 → 8% 0.3 → 12%+ ~0; stairs 0.3 | Finer DEM / lidar |

**Hard exclusions (never routed):** `highway=motorway/trunk` and their links, `access=private/no`, `dog=no`, construction, secondary+ roads with no sidewalk, driveways, and secondary+ roads whose sidewalks are mapped separately (walk the sidewalk ways; pieces ≤30 m stay as crossing connectors). Crossings of tertiary+ roads count as busy-road crossings.

### Weather layer (Open-Meteo)
- **Heat:** air ≥ 77°F and sunny/UV high → hot-pavement warning; shade and grass weights boosted, surface factor prefers unpaved.
- **Cold / winter:** ≤ 32°F with recent snow → de-icer/salt warning; grass weight boosted.
- **Rain:** recent heavy precipitation → unpaved/grass penalized for mud.
- **Dark:** after sunset → lighting weight enabled.

## 5. Dog profiles (preset weights, user-adjustable)

| Profile | Emphasis |
|---|---|
| **Everyday** (default; built around Ricky) | quiet 0.30 · grass 0.25 · sidewalk 0.20 · terrain 0.15 · crossings 0.15 · crowds 0.10 · shade 0.05 |
| **Quiet / reactive** | quiet 0.35 · crowds 0.20 · crossings 0.15 · sidewalk 0.15 · grass 0.10 · shade 0.05 |
| **Sniffy explorer** | grass 0.35 · shade 0.15 · quiet 0.15 · sidewalk 0.15 · crowds 0.10 · crossings 0.10 |
| **Potty break** | Short; nearest good grass first, minimal crossings, return fast |
| **Senior / hot day** | shade 0.30 · surface 0.20 · sidewalk 0.20 · quiet 0.15 · benches bonus · elevation (later) |

Amenities are additive bonuses, not weighted factors. Weather modifies weights at runtime.

## 6. Scoring model

- **Edge quality** `q ∈ [0,1]` = weighted mean of factor subscores under the active profile (+ weather modifiers), × a **traffic veto** `min(1, quiet/0.7)^0.75` so busy streets can never score well on sidewalks and lighting alone.
- **Edge routing cost** = `length × (1 + α·(1 − q))`, α ≈ 3 (tunable). A great street costs roughly its length; a bad one costs up to 4× — so the router will detour for quality, but not absurdly.
- **Route score (0–100)** = length-weighted mean of `q` × 100, then adjusted for: distance fit vs. target, crossing penalty, retracing penalty (loops shouldn't double back much), destination bonus, amenity bonus.
- Everything must be explainable — reasons bubble up from factors to the route's "why" line.

## 7. Route generation

1. Geocode start. Fetch OSM data via Overpass for a bbox of radius ≈ target/2 + margin; cache by tile in IndexedDB.
2. Build a walkable graph (nodes, edges with tags). Precompute edge features using Flatbush spatial queries (proximity to grass, trees, major roads, rail, POIs).
3. **Loops:** sample 24–48 candidate loop shapes (two intermediate waypoints at varied bearings and radii scaled to target distance), route each leg with A* on the cost function, penalizing edges already used in earlier legs to avoid retracing. Keep candidates within tolerance, score, select top 3 with < 40% pairwise overlap.
4. **Destinations:** (dog parks get no special bonus — neutral) find candidate destinations within reach, route to each, rank by destination quality × route quality × fit. Out-and-back may return on a different path if it scores better.
5. All of steps 2–4 run in a Web Worker; UI shows progress.

## 8. Calibration

Mike will walk streets around the test fixture and record ground truth in `fixtures/ground-truth.json`:

```json
[{ "street": "Example St between A and B", "rating": 1-5, "notes": "busy at rush hour, no grass" }]
```

The Phase 1 debug heatmap must be compared against this. The model is only as good as its agreement with a person who has actually walked the streets with a dog.

## 9. Phases (stop after each)

0. **Plan** — read this spec, propose file tree, module interfaces, and key type definitions (Edge, Node, FactorResult, Profile, Route). List any concerns or open questions. No code.
1. **Data + graph + heatmap** — Overpass fetch + cache, graph build, edge features, all factor functions with unit tests, map with the debug layer coloring every street by quality around the fixture. *This is the checkpoint that matters most.*
2. **Loop routing** — input panel (duration/distance, pace, profile), loop generator, top-3 routes with score breakdowns and "why."
3. **Destinations** — destination discovery and ranking, out-and-back and one-way modes.
4. **Weather + time of day** — Open-Meteo integration, runtime weight modifiers, warnings.
5. **Ship** — PWA install, GPX export, share links, GitHub Pages deploy workflow, "Dog Walk Score" for any address (for people comparing apartments before a move).
6. **Later** — noise and canopy rasters, community street reports, native iOS wrapper.

## 10. Non-goals for v1

No accounts, no backend, no paid APIs, no social features. Anything that needs a server or a key gets flagged and deferred.
