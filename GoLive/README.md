# GoLive

Press the Action Button, be live on YouTube.

GoLive is a native iOS app (SwiftUI). Opening it creates a YouTube broadcast titled
**Live stream N**, pushes the camera and microphone to YouTube over RTMPS, and YouTube
flips it live as soon as video arrives. N starts at 1 and counts up; you can change it in
the app's settings.

## One-time setup (about 10 minutes)

### 1. YouTube: enable live streaming

Go to <https://www.youtube.com/features> signed in as the channel's Google account and
enable **Live streaming**. The first activation can take up to 24 hours. If the channel
has streamed before, this is already done.

### 2. Google Cloud: create an OAuth client ID

The app talks to YouTube as *you*, so it needs your own (free) Google API project.

1. <https://console.cloud.google.com/projectcreate> — create a project (any name).
2. <https://console.cloud.google.com/apis/library/youtube.googleapis.com> — **Enable** the YouTube Data API v3.
3. <https://console.cloud.google.com/auth/overview> — **Get started**: app name `GoLive`,
   your email, audience **External**, finish.
4. <https://console.cloud.google.com/auth/audience> — press **Publish app** so the status is
   *In production*. (Left in *Testing*, Google signs you out every 7 days. Publishing needs
   no review for personal use; you'll just see an "unverified app" screen once at sign-in —
   choose *Advanced → Go to GoLive*.)
5. <https://console.cloud.google.com/auth/clients/create> — application type **iOS**,
   bundle ID `work.kushman.GoLive`. Create, then copy the **Client ID**
   (it ends in `.apps.googleusercontent.com`).

### 3. Build and install

Needs Xcode 26 or newer. Plug in the iPhone (unlocked, Developer Mode on) and run:

```bash
cd GoLive
./run.sh YOUR-CLIENT-ID.apps.googleusercontent.com
```

The script finds your signing team and phone, builds, installs, and launches. Later
rebuilds are just `./run.sh`. With a free Apple developer account the install expires after
7 days — re-run the script to refresh it.

Prefer Xcode? `open GoLive.xcodeproj`, pick your team under Signing & Capabilities, and
run. You can paste the client ID into the app's first screen instead.

### 4. Sign in

On the app's first screen tap **Sign in with Google** and choose the account (and channel)
you stream to. The channel name shows on the home screen so you can confirm it's the right one.

### 5. Action Button

Settings → Action Button → **Shortcut** → GoLive → **Go Live**.
(Or pick *Open App → GoLive*; the app goes live on open either way.)

## Using it

- **Press the Action Button** → the app opens and starts streaming. Expect roughly 5–10
  seconds before YouTube shows it as live; the badge switches from CONNECTING to LIVE.
- **Hold the phone sideways while it starts** for a landscape stream; upright for vertical.
  Orientation is fixed for the length of the stream.
- **Square button** ends the stream. **Leaving the app or locking the phone also ends it** —
  iOS doesn't allow camera capture in the background.
- Mic mute, camera flip, torch, and a share link to the video are on screen while live.
- Cancel before it goes live and the empty broadcast is deleted and its number reused.
- **Settings** (gear, when not live): next stream number, Public / Unlisted / Private
  (default Public), 720p / 1080p, front camera, and whether opening the app goes live automatically.

## How it works

| File | Job |
| --- | --- |
| `GoogleAuth.swift` | OAuth (authorization code + PKCE), refresh token in the Keychain |
| `YouTubeAPI.swift` | Live Streaming API: create broadcast, bind stream, status, end |
| `Broadcaster.swift` | Camera/mic capture and RTMPS publishing via [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) |
| `LiveController.swift` | The start → live → end sequence, reconnects, numbering |
| `LiveView.swift` etc. | Interface |
| `GoLiveIntent.swift` | "Go Live" action for the Action Button / Shortcuts / Siri |

Each stream costs about 150 units of the YouTube API's free 10,000-unit daily quota.
