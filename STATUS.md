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

## 2026-11-14 — Cull (macOS disk-space cleaner)

Task / owner / branch: build a native macOS app to detect and cull unnecessary files and caches so the disk stops hitting critical levels / Claude Code cloud session / `claude/relaxed-fermi-r41ti3`.
Completed: new `cull/` Swift package with three targets. `CullCore` (Foundation-only engine: rule catalog, POSIX sizer, independent safety guard, scanner, culler), `cull` (CLI, dry run by default), `CullApp` (SwiftUI app, macOS 14+, bundled by `build.sh` with an icon). `.github/workflows/cull.yml` builds and tests on a macOS runner, path-filtered to `cull/**`. Site files unchanged.
Validation actually performed: VALIDATION_PLACEHOLDER
Open issues / blockers: OPEN_PLACEHOLDER
Next step: on the Mac, `cd cull && ./build.sh && open build/Cull.app`. Review the first scan before culling, grant Full Disk Access if the Trash and backups should be included, then record how it behaves on a real, lived-in home folder here.
Delivery (local, pushed, merged, deployment verified): pushed to the branch above with draft PR never-nude/work#4; not merged. Nothing is deployed. This repository is the kushman.work Pages site, so merging would publish the `cull/` sources with it; keeping it as a branch or moving it to its own repository are both reasonable.

## Future handoff fields

Task / owner / branch:
Completed:
Validation actually performed:
Open issues / blockers:
Next step:
Delivery (local, pushed, merged, deployment verified):
