# Shared project handoff — work

Setup date: 2026-09-19. This section records repository setup, not a full application audit.

## Repository identity

- Repository: https://github.com/never-nude/work
- Default branch observed: `main`.
- Scope: this repository only. Related versions are not automatically interchangeable.

## Evidence and current state

README identifies this repository as the static GitHub Pages site for kushman.work.

README.md was inspected for project context (observed blob `9dea26be041a740ae2c33b9825635d249a555dd8`). Its existing statements are not new runtime verification.

## Handoff setup

- Task: shared Codex context across this chat and two computer checkouts.
- Owner of this documentation task: ChatGPT Codex session.
- Setup branch: `codex/shared-handoff-20260919`.
- Changes: AGENTS.md session-start/session-finish rules plus this status record; application code unchanged.
- Validation: checked availability of root instructions and status; preserved existing documents/history. No application runtime tests were performed for this documentation-only task.
- Delivery: check the setup pull request in GitHub for merge status. If these changes are on the remote default branch, they are integrated there; this does not establish deployment success or local computer synchronization.

## Unverified local work

Neither computer's checkout, uncommitted changes, unpushed commits, local paths, running tasks, nor separate Codex conversations has been inspected. Do not mark either machine synchronized based on these files alone.

## Next session

1. Read AGENTS.md and existing project instructions.
2. Inspect the local remote/branch and preserve pending work; fetch and safely integrate the shared default branch.
3. Record discovered unfinished work, its branch, actual validation, and next step here. Reconcile it with remote history before implementation.
4. At task completion, update this handoff and publish it through the existing repository workflow when authorized.

## Future handoff fields

Task / owner / branch:
Completed:
Validation actually performed:
Open issues / blockers:
Next step:
Delivery (local, pushed, merged, deployment verified):

---

## 2026-09-29 — Sniffari Phase 0 + Phase 1 (Claude Code, cloud session)

Task / owner / branch: Sniffari dog-walk route planner, new project in `sniffari/`. Claude Code cloud session. Branch `claude/loving-wozniak-aqkmrr` (draft PR against `main`).
Completed:
- Phase 0 plan with open questions: `sniffari/docs/PLAN.md`.
- Phase 1: Overpass tile fetch + IndexedDB cache, graph build, edge features (Flatbush), all factor functions + exclusions, profiles, edge scoring, Web Worker pipeline, MapLibre street-quality heatmap with a tap-to-inspect breakdown, synthetic fixture, `fixture:fetch` and `calibrate` scripts.
Validation actually performed: `npm test` (77 passing), `npm run typecheck`, `npm run build`; dev and production builds driven in headless Chromium on `?fixture=synthetic` (heatmap renders, inspector works on phone and desktop layouts).
Open issues / blockers:
- This environment's network policy blocks overpass-api.de, nominatim.openstreetmap.org and tiles.openfreemap.org, so live data, the real White Plains fixture and the basemap style were NOT verified.
- `sniffari/` sits inside the kushman.work Pages repo; merging to `main` would publish an unbuilt dev page at /sniffari/. Decide on a dedicated repo before merging.
- Brand artwork (app icon + logo) was shared in chat only; drop the PNGs into `sniffari/public/brand/`.
- Model decisions awaiting Mike: see PLAN.md §6.
Next step: locally, `cd sniffari && npm install && npm run fixture:fetch && npm run dev`, open `/?fixture=white-plains`, review the heatmap, answer PLAN.md §6, start filling `fixtures/ground-truth.json`. Phase 2 (loop routing) waits for go-ahead.
Delivery: pushed to the feature branch; not merged; not deployed.

### 2026-09-29 (later) — scoring changes from Mike's review
Completed: traffic veto (busy streets score low), terrain factor from Terrarium elevation tiles (worker fetch+cache, saved by `fixture:fetch`, decoded in `calibrate`), separately-mapped sidewalks rule, tertiary crossings, dog parks neutral with an opt-in toggle, grass rewards nearby green, new default "Everyday" profile. SPEC.md/PLAN.md updated with the decisions.
Validation: 94 tests passing, typecheck + build pass, synthetic fixture re-screenshotted (Main St now red). Elevation tiles (s3.amazonaws.com) not reachable from this environment — terrain verified only with synthetic slopes.
Next step: unchanged — run `npm run fixture:fetch` locally and review White Plains.

### 2026-09-29 (later) — "Optimize route in view"
Completed: A* router with busy-crossing node costs (only when going across a busy road), loop generator (16 bearings × 3 radii, two-waypoint triangles, reuse penalty, spur trimming, top-3 with <40% overlap), one-way "somewhere else" with alternatives, route scoring (length-weighted q, crossings blend, retrace/fit penalties, amenity bonus, why line, warnings), worker `plan` message, UI: floating Optimize button, walk length/pace/finish panel, end-point picking, route cards with breakdowns, routes drawn over a dimmed heatmap.
Validation: 103 tests passing; typecheck + build; both flows driven in headless Chromium on the synthetic fixture (loop and somewhere-else).
Open: not tried on real White Plains data (network-blocked here); GPS start untested in headless (falls back to the pin); POIs along routes not yet listed.

### 2026-09-30 — phone alpha prep + Mike's field notes
Completed: street scores follow the map view (auto-load on pan/zoom, circle = loaded area); locate-me button (GPS, IP fallback) + live position dot; address search button; long-press / right-click drops a pin with reverse-geocoded address → Start here / Finish here; "Somewhere else" opens a finish picker (tap, search, or crosshair); unnamed footways described from surroundings ("Sidewalk · Main Street", "Path in Cottage Green"); planning area = view ∪ start ∪ finish + margin; finish never snaps onto the start corner. Capacitor iOS project (`sniffari/ios`), location permission, placeholder icon, `npm run ios`, docs/IOS.md.
Validation: 107 tests; typecheck/build; flows driven in headless Chromium on the synthetic fixture. The iOS project was generated on Linux and has NOT been built in Xcode yet.
Next: on the Mac, `npm run ios` and Run on the iPhone (docs/IOS.md); TestFlight if the paid developer account is available.
