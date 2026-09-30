# Sniffari — Claude Code project guide

Sniffari generates the best dog-walking routes from a starting point. The user sets a target walk (minutes or miles, plus a pace), and the app returns the top routes and destinations, scoring every street segment on the things that actually make a dog walk good or bad: sidewalks, quiet, grass, shade, crossings, crowds, amenities, rules, and weather.

The full product spec is in `docs/SPEC.md`. Read it before writing code.

## Ownership rules (important)

- **Mike owns architecture, data models, and core behavior.** You propose; he decides. Do not change the stack, the scoring model, the graph data structures, or the route-generation approach without asking first. Small implementation choices inside a module are yours — just make them.
- **Visual design is delegated to you.** Defaults: dark mode only, clean modern sans-serif (no serifs, no italics), generous type sizes, strong contrast, legibility first, purple accent. Mobile-first — primary use is one-handed on an iPhone while holding a leash.
- **Git:** never push, never add remotes, never change git config. Commit locally with clear messages when a phase is done, and print any push commands for Mike to copy-paste.
- **Work in phases** (see SPEC §9). Finish a phase, get it running, show how to verify it, then stop and wait. Don't roll into the next phase uninvited.

## Stack

- Vite + React + TypeScript (strict), Zustand for state
- MapLibre GL JS for the map; free keyless basemap (OpenFreeMap dark-style or Protomaps — verify which dark style is currently available)
- Turf.js for geometry, Flatbush for spatial indexing
- Routing runs **client-side in a Web Worker** on a graph built from OpenStreetMap data (Overpass API). No backend in v1.
- Open-Meteo for weather (free, no key)
- Geocoding: Nominatim (respect 1 req/sec, set a descriptive User-Agent/Referer) with Photon as fallback
- idb-keyval for IndexedDB caching of Overpass tiles (7-day TTL)
- vite-plugin-pwa for installability; Vitest for tests
- Deploy target: GitHub Pages via GitHub Actions

## Commands

```
npm install
npm run dev        # local dev
npm run test       # vitest
npm run build      # production build
```

## Code layout (target)

```
src/
  data/        overpass.ts, cache.ts, geocode.ts, weather.ts
  graph/       buildGraph.ts, edgeFeatures.ts, spatialIndex.ts
  scoring/     factors/*.ts (one file per factor), profiles.ts, scoreEdge.ts, scoreRoute.ts
  routing/     astar.ts, loopGenerator.ts, destinations.ts, worker.ts
  ui/          map/, panels/, components/
  state/       store.ts
fixtures/      cached Overpass responses + ground-truth.json for tests
docs/          SPEC.md
```

## Conventions

- Every factor is a pure function `(edge, context) => subscore in [0,1]` plus a human-readable reason string. Factors never know about weights; profiles apply weights. This keeps scoring explainable and tunable.
- Every route shown to the user must be explainable: a 0–100 score, per-factor breakdown, and a one-line "why."
- Be a polite API citizen: cache aggressively, debounce, batch Overpass queries by tile, never hammer public endpoints in tests (use fixtures).
- No API keys in the repo. If a phase ever needs one, stop and ask.

## Test fixture

Primary real-world test location: **AVE Hamilton Green, 25 Cottage Place, White Plains, NY 10601** (downtown White Plains, a few blocks from the Metro-North station — a genuinely mixed environment: busy arterials, rail, commercial strips, and quieter residential streets nearby). Geocode it once, save the result and the Overpass response to `fixtures/`, and use those in tests.

`fixtures/ground-truth.json` holds Mike's real-world ratings of specific streets (added after he walks them). Scoring changes should be checked against it.
