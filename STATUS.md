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
Validation actually performed: unsigned iOS device build (`xcodebuild`, Xcode 26, macOS runner) succeeded at commit `1577db0` — workflow run 44431484409. The first run failed only because the runner used Xcode 16.4; HaishinKit 2.3.0 requires the iOS 26 SDK, so building needs Xcode 26+. Not run on a physical iPhone and not tested against a real YouTube channel from this session — no Mac or phone was attached.
Open issues / blockers: Needs the owner's Google Cloud OAuth client ID (iOS type, bundle ID `work.kushman.GoLive`) and a first on-device run; `run.sh` device/team auto-detection is untested on real hardware.
Next step: Follow `GoLive/README.md` on a Mac with the iPhone connected; report any on-device issue.
Delivery (local, pushed, merged, deployment verified): pushed to the branch above with a draft PR; not merged; nothing deployed.

### 2026-11-19 update — GoLive first on-device run

Completed: sign-in hardening and strict client-ID validation (commit `930fe0c`, CI build green). Owner created the Google Cloud project, enabled YouTube Data API v3, and made an iOS OAuth client; the OAuth app is in Testing mode with the owner as a test user (Google sign-in expires every 7 days until the app is published, which needs a homepage and privacy policy URL on the Branding page).
Validation actually performed: owner's Mac built, signed, installed, and launched the app on their iPhone via `GoLive/run.sh` (seen in their terminal output). Whether sign-in and an actual YouTube broadcast succeeded was reported only as "job well done" — not independently observed from this session.
Next step: set the Action Button (Settings → Action Button → Shortcut → GoLive → Go Live); decide whether to merge the draft PR; optionally publish the OAuth app to stop the weekly re-sign-in.
Delivery: pushed to `claude/intelligent-mccarthy-ikawlj`, draft PR open, not merged.

### 2026-11-20 update — stabilization on by default

Completed: `Stabilization` setting (Off / Steady / Smoother / Smoothest), default Steady = iOS 26 `.lowLatency`, falling back to `.standard` (chosen because cinematic modes buffer ~1 s of frames that would be lost if the phone is destroyed). `SyncGate` between mixer and RTMP stream keeps audio/video aligned under stabilization delay; an adversarial review found a pre-arm race (stale frame could set the video zero) — fixed by keeping the gate closed until armed.
Validation actually performed: CI compile only (see PR checks). Not run on device; which stabilization modes the iPhone 17 Pro supports at 720p/1080p is unverified (the app checks at runtime and steps down).
Next step: owner pulls and rebuilds; check a Smoother/Smoothest stream for lip sync.

### 2026-11-21 update — first verified live stream

Validation actually performed: owner streamed from the iPhone with the diagnostics build (`c64a3d7`); the app log showed YouTube "ingest active, health good", LIVE 7 s after start, 70 s of 1080p at ~30 fps / 6 Mbps, clean end. Replay appeared on the channel ("Processing will begin shortly"). On this phone the 1080p format offers `.standard` stabilization, not `.lowLatency`.
Completed since: in-app Diagnostics log + stream-health polling (`12ca45f`/`c64a3d7`); leftover empty broadcasts deleted on launch (`ed00331`). An "Upcoming" placeholder from an earlier interrupted start predates that tracking and must be deleted by hand once.
Open: the earlier "stuck at Upcoming" report did not reproduce; cause unknown (possibly checked before the ~7 s flip). Smoother/Smoothest lip-sync not yet checked on device.
Delivery: pushed; draft PR open; not merged.

### 2026-11-21 wrap-up — owner confirmed "works"

State: GoLive on branch `claude/intelligent-mccarthy-ikawlj`, head `fe61cad` (app) + this status note; CI green; draft PR never-nude/work#5 open, not merged. Owner streamed live with this build and confirmed it works.
Shipped since first on-device run: stabilization setting (default Steady: iOS 26 `.lowLatency`, else `.standard`; on the owner's iPhone at 1080p the active mode logged as `.standard`); SyncGate for audio/video start alignment (closed until armed); full RTMP onMetaData restored by priming the stream with one pre-publish sample of each (`2f6e1b7`, adversarially verified against HaishinKit 2.3.0); in-app Diagnostics log + YouTube ingest health polling; deletion of empty leftover broadcasts on launch; run.sh refuses stale builds and has `--console`.
Findings: the owner's pull history (`Updating 930fe0c..12ca45f` at 7:16 PM local on 11-20) shows Live streams 7 and 8 were made by the pre-stabilization build; their replays sat in "Processing will begin shortly" exactly like stream 9 (new build). Research: nothing in YouTube docs ties replay processing to short/vertical/1080p streams or onMetaData; the app already sets the documented recipe for immediate replay (recordFromStart default true + enableDvr true). Treat "Processing" as a YouTube-side queue unless a replay is still unplayable after ~24 h or reports failed/terminated.
Environment: www.youtube.com was added to the "Storage Monitor" cloud environment's allowed hosts to read a video's oEmbed (watch pages hit Google's bot check from the cloud IP).
Open / next: re-check the 11-20 replays; if any stay stuck ~24 h, consider adding post-stream polling of videos.list (status, processingDetails) to Diagnostics. Optional ideas not built: keep streaming audio while the app is backgrounded/locked (needs background audio mode); save a local copy as backup. Merging the PR is the owner's call.
