# Sniffari

Best dog-walking routes from where you're standing. Every street segment is scored on what makes a
dog walk good or bad — sidewalks, quiet, grass, shade, crossings, crowds, surface, lighting,
amenities, rules — from OpenStreetMap, entirely in the browser.

Status: **Phase 1** (data + graph + street-quality heatmap). See `docs/SPEC.md` for the product,
`docs/PLAN.md` for architecture and open questions, `CLAUDE.md` for working rules.

## Run it

```sh
cd sniffari
npm install
npm run dev                      # http://localhost:5173
```

- `http://localhost:5173/?fixture=synthetic` — offline test grid, loads instantly.
- `http://localhost:5173/` — live OpenStreetMap around the White Plains fixture; press **Score streets**.
- Tap any street for its score, per-factor breakdown with reasons, raw OSM tags, and a
  **Copy ground-truth stub** button for calibration.
- **Dog** and **When** chips re-score instantly without refetching.

## Real-world fixture + calibration

```sh
npm run fixture:fetch            # one Nominatim + one Overpass request → fixtures/white-plains.*
npm run dev                      # then open /?fixture=white-plains
npm run calibrate                # model vs fixtures/ground-truth.json, with Spearman ρ
```

Ground-truth entries (SPEC §8, plus optional locators the app fills for you):

```json
{ "street": "Oak Ave (way 123)", "wayIds": [123], "at": { "lat": 41.03, "lon": -73.76 },
  "rating": 4, "notes": "quiet, big lawns", "profile": "quiet", "hour": 18 }
```

## Checks

```sh
npm test                         # vitest — factors, graph build, features, cache, tiles
npm run typecheck
npm run build
```

## Brand

Drop `app-icon.png` and `logo.png` into `public/brand/` (see the README there).
