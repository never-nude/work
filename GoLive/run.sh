#!/bin/bash
# Build GoLive, install it on the connected iPhone, and launch it.
#
#   ./run.sh                       build + install + launch
#   ./run.sh <google-client-id>    same, and bake the OAuth client ID into the app
#
# Optional overrides:  TEAM_ID=ABCDE12345  DEVICE="Michael's iPhone"  ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="work.kushman.GoLive"

# --- Google client ID (remembered locally, never committed) -----------------
if [ "${1:-}" != "" ]; then echo "$1" > .client_id; fi
CLIENT_ID="$(cat .client_id 2>/dev/null || true)"

# --- Signing team -----------------------------------------------------------
TEAM="${TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  TEAM="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
fi
if [ -z "$TEAM" ]; then
  echo "Couldn't find an Apple Development signing certificate."
  echo "Sign in once at Xcode → Settings → Accounts, or re-run with TEAM_ID=<your team id> ./run.sh"
  exit 1
fi
echo "Signing team: $TEAM"

# --- Device -----------------------------------------------------------------
DEVICE_ID="${DEVICE:-}"
if [ -z "$DEVICE_ID" ]; then
  TMP="$(mktemp)"
  xcrun devicectl list devices --json-output "$TMP" >/dev/null 2>&1 || true
  DEVICE_ID="$(/usr/bin/python3 - "$TMP" <<'PY' || true
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
phones = [d for d in devices if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
def rank(d):
    c = d.get("connectionProperties", {})
    return (c.get("tunnelState") == "connected", c.get("pairingState") == "paired")
phones.sort(key=rank, reverse=True)
if phones:
    print(phones[0].get("hardwareProperties", {}).get("udid") or phones[0]["identifier"])
PY
)"
  rm -f "$TMP"
fi
if [ -z "$DEVICE_ID" ]; then
  echo "No iPhone found. Plug it in (or put it on the same Wi-Fi), unlock it, trust this Mac, then re-run."
  exit 1
fi
echo "Device: $DEVICE_ID"

# --- Build ------------------------------------------------------------------
xcodebuild -project GoLive.xcodeproj -scheme GoLive -configuration Release \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -skipPackagePluginValidation -skipMacroValidation \
  DEVELOPMENT_TEAM="$TEAM" GOOGLE_CLIENT_ID="$CLIENT_ID" \
  build | grep -E "error:|warning: unable|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Release-iphoneos/GoLive.app"
[ -d "$APP" ] || { echo "Build failed. Re-run with: xcodebuild ... (see run.sh) for the full log."; exit 1; }

# --- Install + launch -------------------------------------------------------
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || \
  echo "Installed. Unlock the phone and tap GoLive (first launch may need Settings → General → VPN & Device Management → trust)."
