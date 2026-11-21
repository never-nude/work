#!/bin/bash
# Build GoLive, install it on the connected iPhone, and launch it.
#
#   ./run.sh                       build + install + launch
#   ./run.sh <google-client-id>    same, and bake the OAuth client ID into the app
#   ./run.sh --console             same, and stay attached to the app's log (shows every step of a stream)
#
# Optional overrides:  TEAM_ID=ABCDE12345  DEVICE="<device name or UDID>"  ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="work.kushman.GoLive"

# --- Google client ID (remembered locally, never committed) -----------------
CONSOLE=0
if [ "${1:-}" = "--console" ]; then CONSOLE=1; shift; fi
if [ "${1:-}" != "" ]; then
  CANDIDATE="$(printf '%s' "$1" | tr -d '[:space:]')"
  if printf '%s' "$CANDIDATE" | grep -Eq '^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$'; then
    echo "$CANDIDATE" > .client_id
  else
    echo "Not a Google client ID: $CANDIDATE"
    echo "It should look like 1234567890-abc123.apps.googleusercontent.com (copy it from Google Cloud → Clients)."
    exit 1
  fi
fi
CLIENT_ID="$(cat .client_id 2>/dev/null || true)"
if ! printf '%s' "$CLIENT_ID" | grep -Eq '^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$'; then
  rm -f .client_id
  CLIENT_ID=""
fi
echo "Client ID: ${CLIENT_ID:-none baked in (paste it in the app)}"

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
if [ -n "$(find GoLive -name '*.swift' -newer "$APP/GoLive" 2>/dev/null)" ]; then
  echo "Build failed (the app on disk is older than the source). Fix the errors above and re-run."
  exit 1
fi

# --- Install + launch -------------------------------------------------------
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
if [ "$CONSOLE" = "1" ]; then
  echo "Launching with the app's log attached. Press Ctrl-C to stop."
  exec xcrun devicectl device process launch --console --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"
fi
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID" || \
  echo "Installed. Unlock the phone and tap GoLive (first launch may need Settings → General → VPN & Device Management → trust)."
