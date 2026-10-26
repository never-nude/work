#!/bin/zsh
# Builds Loopsmith.app from the Swift package. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP=Loopsmith
OUT=build/$APP.app

swift build -c release

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp ".build/release/$APP" "$OUT/Contents/MacOS/$APP"
cp Info.plist "$OUT/Contents/Info.plist"

# Ad-hoc signature so macOS remembers the Screen Recording grant between builds.
codesign --force --sign - "$OUT" >/dev/null

echo "Built $OUT"
echo "Run:  open \"$OUT\""
