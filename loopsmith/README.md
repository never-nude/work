# Loopsmith

A small native macOS GIF maker. Drop in a video or record part of your screen, trim it, pick a size and frame rate, export a looping GIF.

Requires macOS 15 or newer and the Xcode command line tools (`xcode-select --install`). No Xcode project; it's a Swift package.

## Build and run

```sh
cd loopsmith
./build.sh
open build/Loopsmith.app
```

`build.sh` compiles the package in release mode, wraps the binary in `build/Loopsmith.app` with `Info.plist`, and ad-hoc signs it so macOS remembers the Screen Recording permission between rebuilds.

For a quick iteration loop without the bundle:

```sh
swift run
```

Screen recording from `swift run` attributes the permission to Terminal rather than Loopsmith. Use the bundled app when testing recording.

## Use

- Drop a video on the window, or press ⌘O.
- ⌘R opens the screen recorder. Pick a display or a single window, then Start. The Loopsmith window floats above everything and stays out of display captures. ⌘⇧R or the Stop button ends the recording and loads it into the editor.
- Drag the blue handles to set the in and out points, or press I and O at the playhead. Space plays the selection. Playback loops inside the trim.
- Width, frame rate, speed, and Boomerang (forward then backward) are in the settings row. The caption shows the output size and frame count.
- ⌘E exports. The result card shows the file size; drag the card into Messages, Slack, Finder, or anything that takes a file.

## First run: Screen Recording permission

The first time you start a recording, macOS asks to allow Screen & System Audio Recording for Loopsmith. Allow it, then relaunch the app. If the list of displays and windows is empty, the permission is missing; the sheet has a button that opens the right settings pane.

## Layout

- `Sources/Loopsmith/LoopsmithApp.swift`: app entry, menu commands.
- `Sources/Loopsmith/Studio.swift`: editor state, preview player, load/export/record actions.
- `Sources/Loopsmith/ContentView.swift`: empty state, editor, export card, recorder sheet.
- `Sources/Loopsmith/TrimBar.swift`: the in/out range control.
- `Sources/Loopsmith/GifExporter.swift`: AVAssetImageGenerator → ImageIO GIF writer.
- `Sources/Loopsmith/ScreenRecorder.swift`: ScreenCaptureKit recording to a temporary `.mov`.
