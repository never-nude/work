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
