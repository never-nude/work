#!/usr/bin/env bash
# Sniffari: everything from "latest code" to "on my phone", in one command. Run from sniffari/.
#
#   npm run ship      # update → test → build → sign → upload to TestFlight (default)
#   npm run phone     # update → build → install straight onto the iPhone (USB or same Wi-Fi), no Xcode window
#   npm run pack      # (re)run the Pack / Supabase / push setup only
#
# First run asks for a few one-time things (and opens the right Apple pages); later runs just go.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-testflight}"
ROOT="$(pwd)"
PROJ="ios/App/App.xcodeproj"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

say()  { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ask()  { local v; read -r -p "  $1 " v; printf '%s' "$v"; }
envset() { touch .env.local; grep -v "^$1=" .env.local > .env.local.tmp || true; printf '%s=%s\n' "$1" "$2" >> .env.local.tmp; mv .env.local.tmp .env.local; }
envget() { grep -s "^$1=" .env.local | head -1 | cut -d= -f2- || true; }

# ------------------------------------------------------------------ 1. tools + latest code
say "Checking your Mac"
[ "$(uname)" = Darwin ] || die "Run this on the Mac."
command -v xcodebuild >/dev/null || die "Xcode isn't installed (App Store → Xcode)."
command -v node >/dev/null || die "Node isn't installed (brew install node)."
ok "$(xcodebuild -version | head -1), node $(node -v)"

say "Getting the latest Sniffari"
# Xcode writes your Team into the project file when you pick it in the UI; this script supplies the
# Team itself, so drop that local edit rather than let it block updates.
git checkout -- "$PROJ/project.pbxproj" 2>/dev/null || true
if [ -n "$(git status --porcelain --untracked-files=no -- . ':!.env.local')" ]; then
  warn "You have local changes; updating anyway where possible."
fi
git pull --ff-only --quiet && ok "up to date ($(git log -1 --format=%h))" || warn "couldn't fast-forward — continuing with what you have"

# ------------------------------------------------------------------ 2. Apple team (from Xcode's signed-in account)
say "Finding your Apple developer team"
TEAM="$(envget APPLE_TEAM_ID)"
if [ -z "$TEAM" ]; then
  TEAMS="$(defaults export com.apple.dt.Xcode - 2>/dev/null | plutil -convert json -o - - 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{const j=JSON.parse(s);const all=Object.values(j.IDEProvisioningTeamByIdentifier||j.IDEProvisioningTeams||{}).flat();
      const paid=all.filter(t=>t&&t.teamID&&!t.isFreeProvisioningTeam);
      const seen=new Set();for(const t of (paid.length?paid:all)){if(seen.has(t.teamID))continue;seen.add(t.teamID);console.log(t.teamID+"\t"+(t.teamName||""))}}catch{}})' || true)"
  COUNT="$(printf '%s' "$TEAMS" | grep -c . || true)"
  if [ "$COUNT" = 0 ]; then
    warn "Xcode isn't signed in to your Apple Developer account yet."
    echo "    Xcode is opening: Settings (⌘,) → Accounts → + → Apple ID → sign in. Then come back here."
    open -a Xcode; read -r -p "  Press Return once you're signed in… " _
    exec "$0" "$MODE"
  elif [ "$COUNT" = 1 ]; then
    TEAM="$(printf '%s' "$TEAMS" | cut -f1)"
  else
    echo "$TEAMS" | nl -w2 -s') '
    PICK="$(ask 'Which team? (number)')"
    TEAM="$(printf '%s\n' "$TEAMS" | sed -n "${PICK}p" | cut -f1)"
  fi
  envset APPLE_TEAM_ID "$TEAM"
fi
BUNDLE="$(grep -o "appId: '[^']*'" capacitor.config.ts | cut -d"'" -f2)"
ok "team $TEAM · app $BUNDLE"
export APPLE_TEAM_ID="$TEAM"

# ------------------------------------------------------------------ 3. Pack (Supabase + push), first time only
if [ "$MODE" = pack ] || [ -z "$(envget VITE_SUPABASE_URL)" ]; then
  if [ "$MODE" = pack ] || [ "$(ask 'Set up Pack (live walk sharing) now? [Y/n]')" != n ]; then
    SKIP_REBUILD=1 bash scripts/setup-social.sh
  else
    warn "Skipping Pack — the app works without it; run 'npm run pack' any time."
  fi
  [ "$MODE" = pack ] && exit 0
fi

# ------------------------------------------------------------------ 3b. app icon (the real artwork, not the placeholder)
say "App icon"
ICONSET="ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
if [ ! -f assets/icon.png ]; then
  CANDIDATE="$(ls -t ~/Downloads/*.png ~/Desktop/*.png 2>/dev/null | grep -iE 'sniffari|icon|dog' | head -1 || true)"
  if [ -n "$CANDIDATE" ] && [ "$(ask "Use $(basename "$CANDIDATE") as the app icon? [Y/n]")" != n ]; then
    SRC="$CANDIDATE"
  else
    echo "    Drag the app icon image (the purple sniffing dog) into this window, then press Return."
    echo "    (Or just press Return to keep the placeholder for now.)"
    SRC="$(ask '>')"; SRC="${SRC%\"}"; SRC="${SRC#\"}"; SRC="${SRC//\\ / }"; SRC="$(echo "$SRC" | sed "s/^'//; s/'$//; s/ *$//")"
  fi
  if [ -n "${SRC:-}" ] && [ -f "$SRC" ]; then
    mkdir -p assets
    # 1024×1024, square-cropped, and flattened (App Store rejects icons with transparency).
    TMP="$BUILD/icon-work"; rm -rf "$TMP"; mkdir -p "$TMP"
    sips -s format png "$SRC" --out "$TMP/src.png" >/dev/null
    W="$(sips -g pixelWidth "$TMP/src.png" | awk '/pixelWidth/{print $2}')"
    H="$(sips -g pixelHeight "$TMP/src.png" | awk '/pixelHeight/{print $2}')"
    SIDE=$(( W < H ? W : H ))
    sips -c "$SIDE" "$SIDE" "$TMP/src.png" --out "$TMP/sq.png" >/dev/null
    sips -z 1024 1024 "$TMP/sq.png" --out "$TMP/1024.png" >/dev/null
    sips -s format jpeg -s formatOptions best "$TMP/1024.png" --out "$TMP/flat.jpg" >/dev/null
    sips -s format png "$TMP/flat.jpg" --out assets/icon.png >/dev/null
    ok "icon prepared from $(basename "$SRC")"
  fi
fi
if [ -f assets/icon.png ]; then
  cp assets/icon.png "$ICONSET"
  mkdir -p public/brand && cp assets/icon.png public/brand/app-icon.png
  ok "app icon installed (also used as the logo in the app's top bar)"
  git add assets/icon.png public/brand/app-icon.png "$ICONSET" 2>/dev/null || true
else
  [ "$MODE" = testflight ] && die "No app icon yet — TestFlight builds shouldn't ship the placeholder. Re-run and drag the icon in."
  warn "still using the placeholder icon"
fi

# ------------------------------------------------------------------ 4. build web app → iOS project
say "Testing and building"
npm install --silent --no-audit --no-fund
npm run -s test > "$BUILD/test.log" 2>&1 || { tail -30 "$BUILD/test.log"; die "Tests failed — nothing was shipped."; }
ok "$(grep -o 'Tests  [0-9]* passed' "$BUILD/test.log" | head -1)"
npm run -s build > "$BUILD/web.log" 2>&1 || { tail -30 "$BUILD/web.log"; die "Web build failed."; }
npx cap sync ios > "$BUILD/sync.log" 2>&1 || { tail -30 "$BUILD/sync.log"; die "Capacitor sync failed."; }
ok "web app built and copied into the iOS project"

VERSION="$(node -p "require('./package.json').version")"
BUILDNUM="$(date +%Y%m%d%H%M)"
SIGN=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILDNUM")

# ------------------------------------------------------------------ 5a. straight to the phone
if [ "$MODE" = phone ]; then
  say "Looking for your iPhone (USB, or same Wi-Fi with 'Connect via network' on)"
  xcrun devicectl list devices --json-output "$BUILD/devices.json" >/dev/null 2>&1 || true
  DEVICE="$(node -e '
    const j=require(process.argv[1]);const d=(j.result?.devices||[]).filter(x=>x.hardwareProperties?.platform==="iOS"&&x.connectionProperties?.tunnelState!=="unavailable");
    if(d[0])console.log(d[0].identifier+"\t"+(d[0].deviceProperties?.name||"iPhone"))' "$BUILD/devices.json" 2>/dev/null || true)"
  [ -n "$DEVICE" ] || die "No iPhone found. Plug it in (and unlock it) once; in Xcode → Window → Devices, tick 'Connect via network' for cable-free installs."
  DEV_ID="$(printf '%s' "$DEVICE" | cut -f1)"; ok "$(printf '%s' "$DEVICE" | cut -f2)"
  say "Building for the phone"
  xcodebuild -project "$PROJ" -scheme App -configuration Debug -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD/dd" -allowProvisioningUpdates "${SIGN[@]}" build > "$BUILD/phone.log" 2>&1 \
    || { grep -E "error:|Signing|provision" "$BUILD/phone.log" | tail -15; die "Build failed (full log: build/phone.log)."; }
  APP="$(ls -d "$BUILD"/dd/Build/Products/Debug-iphoneos/*.app | head -1)"
  xcrun devicectl device install app --device "$DEV_ID" "$APP" >/dev/null
  xcrun devicectl device process launch --device "$DEV_ID" "$BUNDLE" >/dev/null 2>&1 || true
  ok "Sniffari installed and launched on your phone"
  exit 0
fi

# ------------------------------------------------------------------ 5b. archive + upload to TestFlight
say "Signing and archiving (build $BUILDNUM)"
rm -rf "$BUILD/Sniffari.xcarchive"
xcodebuild -project "$PROJ" -scheme App -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$BUILD/Sniffari.xcarchive" -allowProvisioningUpdates "${SIGN[@]}" archive > "$BUILD/archive.log" 2>&1 \
  || { grep -E "error:|Signing|provision" "$BUILD/archive.log" | tail -15; die "Archive failed (full log: build/archive.log)."; }
ok "archived"

if [ "$(envget ASC_APP_CREATED)" != 1 ]; then
  say "One-time: create the app in App Store Connect"
  echo "    Opening appstoreconnect.apple.com → Apps → + → New App:"
  echo "      Platform iOS · Name: Sniffari (if taken: 'Sniffari: Dog Walks') · Language English (U.S.)"
  echo "      Bundle ID: $BUNDLE · SKU: sniffari · User Access: Full Access → Create"
  open "https://appstoreconnect.apple.com/apps"
  read -r -p "  Press Return once the app exists… " _
  envset ASC_APP_CREATED 1
fi

say "Uploading to App Store Connect"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/Sniffari.xcarchive" -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -exportPath "$BUILD/export" -allowProvisioningUpdates > "$BUILD/upload.log" 2>&1 \
  || { grep -E "error|Error" "$BUILD/upload.log" | tail -15; die "Upload failed (full log: build/upload.log)."; }
ok "uploaded build $VERSION ($BUILDNUM)"

say "Done"
echo "  Apple processes the build in ~10–30 min, then it appears in TestFlight."
if [ "$(envget TESTFLIGHT_READY)" != 1 ]; then
  echo "  One-time: App Store Connect → Sniffari → TestFlight → Internal Testing → + → add yourself."
  echo "  On the iPhone, install Apple's 'TestFlight' app and sign in with the same Apple ID."
  envset TESTFLIGHT_READY 1
fi
echo "  Every later update: just run  npm run ship"
open "https://appstoreconnect.apple.com/apps" 2>/dev/null || true
