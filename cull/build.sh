#!/bin/zsh
# Builds Cull.app and the `cull` command-line tool from the Swift package. No Xcode project needed.
#
#   ./build.sh             build into ./build
#   ./build.sh --install   also copy Cull.app to /Applications and `cull` onto your PATH
set -euo pipefail
cd "$(dirname "$0")"

APP=Cull
OUT=build/$APP.app

swift build -c release
BIN=$(swift build -c release --show-bin-path)

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN/CullApp" "$OUT/Contents/MacOS/$APP"
cp Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
cp "$BIN/cull" build/cull

# Sign with a real identity when there is one: macOS ties Full Disk Access to the signature, and an
# ad-hoc signature changes on every build, so the grant would have to be re-ticked each time.
# Set CULL_SIGN_IDENTITY=- to force ad-hoc.
IDENTITY=${CULL_SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }' || true)
fi
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] && codesign --force --sign "$IDENTITY" "$OUT" 2>/dev/null; then
  echo "Signed with $IDENTITY"
else
  codesign --force --sign - "$OUT" >/dev/null 2>&1
  echo "Ad-hoc signed (Full Disk Access will need re-ticking after each rebuild)"
fi

echo "Built $OUT and build/cull"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/$APP.app"
  if [[ -e "$DEST" ]]; then
    # Only ever replace an earlier build of this app, never something else that shares the name.
    EXISTING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DEST/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$EXISTING" != "work.kushman.cull" ]]; then
      echo "$DEST already exists and is a different app (${EXISTING:-unknown}). Leaving it alone."
      exit 1
    fi
    rm -rf "$DEST"
  fi
  cp -R "$OUT" "$DEST"
  echo "Installed $DEST"
  for dir in /usr/local/bin /opt/homebrew/bin; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      cp build/cull "$dir/cull"
      echo "Installed $dir/cull"
      exit 0
    fi
  done
  echo "No writable folder on your PATH for the CLI. To install it yourself:"
  echo "  sudo cp \"$PWD/build/cull\" /usr/local/bin/cull"
else
  echo "Run:  open \"$OUT\""
fi
