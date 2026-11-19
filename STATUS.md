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

## 2026-11-19 — GoLive iOS app (Claude Code cloud session)

Task / owner / branch: New iOS app `GoLive/` (one-press YouTube live streaming). Owner: Claude Code cloud session. Branch: `claude/intelligent-mccarthy-ikawlj`.
Completed: SwiftUI app source, Xcode project (`GoLive/GoLive.xcodeproj`, HaishinKit 2.3.0 via SPM), `GoLive/run.sh` build+install script, `GoLive/README.md` setup guide, CI compile check (`.github/workflows/golive-build.yml`). The static site files are untouched.
Validation actually performed: see the pull request's "GoLive build" check for the compile result (unsigned device build on a macOS runner). Not run on a physical iPhone and not tested against a real YouTube channel from this session — no Mac or phone was attached.
Open issues / blockers: Needs the owner's Google Cloud OAuth client ID (iOS type, bundle ID `work.kushman.GoLive`) and a first on-device run; `run.sh` device/team auto-detection is untested on real hardware.
Next step: Follow `GoLive/README.md` on a Mac with the iPhone connected; report any on-device issue.
Delivery (local, pushed, merged, deployment verified): pushed to the branch above with a draft PR; not merged; nothing deployed.
