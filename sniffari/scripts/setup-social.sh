#!/usr/bin/env bash
# One-command setup for Sniffari's Pack (live walk sharing). Run from sniffari/:
#   bash scripts/setup-social.sh
# Safe to re-run: it reuses an existing project and skips finished steps.
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
ask()  { local v; read -r -p "  $1 " v; printf '%s' "$v"; }
envset() { # envset KEY VALUE → writes/replaces in .env.local
  touch .env.local
  grep -v "^$1=" .env.local > .env.local.tmp || true
  printf '%s=%s\n' "$1" "$2" >> .env.local.tmp
  mv .env.local.tmp .env.local
}
envget() { grep -s "^$1=" .env.local | head -1 | cut -d= -f2- || true; }
json() { node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);console.log(($1)(j)??'')})"; }

# ------------------------------------------------------------------ 0. tools
say "Checking tools"
command -v node >/dev/null || { echo "Node is required (brew install node)"; exit 1; }
if ! command -v supabase >/dev/null; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install supabase/tap/supabase
fi
ok "supabase CLI $(supabase --version)"

# ------------------------------------------------------------------ 1. Supabase project
say "Signing in to Supabase (opens your browser the first time)"
supabase projects list >/dev/null 2>&1 || supabase login
ok "signed in"

REF="$(envget SUPABASE_PROJECT_REF)"
if [ -z "$REF" ]; then
  REF="$(supabase projects list -o json | json 'j => (j.find(p => p.name === "sniffari") || {}).id')"
fi
if [ -z "$REF" ]; then
  say "Creating the 'sniffari' project (free tier, US East)"
  ORG="$(supabase orgs list -o json | json 'j => j[0] && j[0].id')"
  [ -n "$ORG" ] || { echo "No Supabase organization found — create one at https://supabase.com/dashboard, then re-run."; exit 1; }
  DBPASS="$(node -e "console.log(require('crypto').randomBytes(18).toString('base64url'))")"
  envset SUPABASE_DB_PASSWORD "$DBPASS"
  supabase projects create sniffari --org-id "$ORG" --db-password "$DBPASS" --region us-east-1 >/dev/null
  REF="$(supabase projects list -o json | json 'j => (j.find(p => p.name === "sniffari") || {}).id')"
fi
envset SUPABASE_PROJECT_REF "$REF"
ok "project $REF"

say "Waiting for the project to be ready"
for _ in $(seq 1 60); do
  STATUS="$(supabase projects list -o json | json "j => (j.find(p => p.id === '$REF') || {}).status")"
  [ "$STATUS" = "ACTIVE_HEALTHY" ] && break
  printf '.'; sleep 10
done
echo; ok "status $STATUS"

say "Applying the database (dogs, packs, walks, privacy rules)"
DBPASS="$(envget SUPABASE_DB_PASSWORD)"
[ -n "$DBPASS" ] || DBPASS="$(ask 'Database password for this project (Supabase dashboard → Project Settings → Database):')"
supabase link --project-ref "$REF" --password "$DBPASS" >/dev/null
supabase db push --password "$DBPASS" --include-all <<< "y"
ok "database ready"

say "Turning on 6-digit email codes"
if supabase config push --project-ref "$REF" <<< "y" >/dev/null 2>&1; then
  ok "sign-in emails now contain a code"
else
  echo "  ! Couldn't push auth settings automatically. In the dashboard: Authentication → Email Templates → Magic Link,"
  echo "    set the body to the contents of supabase/templates/magic_link.html"
fi

say "Writing app keys to .env.local"
KEYS="$(supabase projects api-keys --project-ref "$REF" -o json)"
ANON="$(printf '%s' "$KEYS" | json 'j => (j.find(k => k.name === "anon") || {}).api_key')"
envset VITE_SUPABASE_URL "https://$REF.supabase.co"
envset VITE_SUPABASE_ANON_KEY "$ANON"
ok ".env.local updated (git-ignored; the service key is never written)"

# ------------------------------------------------------------------ 2. Push notifications
say "Push notifications (Apple)"
if supabase secrets list --project-ref "$REF" 2>/dev/null | grep -q APNS_KEY_ID; then
  ok "APNs secrets already set"
else
  echo "  Apple only allows creating the push key on its website (one time, ~2 min):"
  echo "    1. Opening https://developer.apple.com/account/resources/authkeys/add"
  echo "    2. Name it 'Sniffari APNs', tick 'Apple Push Notifications service (APNs)', Continue → Register → Download"
  echo "    3. Note the Key ID shown, and your Team ID (Membership details page)"
  open "https://developer.apple.com/account/resources/authkeys/add" 2>/dev/null || true
  P8="$(ls -t ~/Downloads/AuthKey_*.p8 2>/dev/null | head -1 || true)"
  if [ -n "$P8" ]; then
    echo "  Found $P8"
    USE="$(ask 'Use this key? [Y/n]')"; [ "${USE:-y}" = "n" ] && P8=""
  fi
  [ -n "$P8" ] || P8="$(ask 'Path to the .p8 file:')"
  KEYID="$(basename "$P8" .p8 | sed 's/AuthKey_//')"
  K2="$(ask "Key ID [$KEYID]:")"; KEYID="${K2:-$KEYID}"
  TEAM="${APPLE_TEAM_ID:-}"
  [ -n "$TEAM" ] || TEAM="$(ask 'Team ID (10 characters):')"
  BUNDLE="$(grep -o "appId: '[^']*'" capacitor.config.ts | cut -d"'" -f2)"
  supabase secrets set --project-ref "$REF" \
    APNS_KEY="$(cat "$P8")" APNS_KEY_ID="$KEYID" APNS_TEAM_ID="$TEAM" APNS_BUNDLE_ID="$BUNDLE" >/dev/null
  ok "APNs secrets set for $BUNDLE (works for Xcode and TestFlight builds)"
fi

say "Deploying the notification sender"
supabase functions deploy notify-walk --project-ref "$REF" >/dev/null
ok "notify-walk deployed"

# ------------------------------------------------------------------ 3. Rebuild the app
[ "${SKIP_REBUILD:-}" = 1 ] && exit 0
say "Rebuilding the iPhone app"
npm install --silent
npm run -s ios:sync
ok "done — in Xcode press ▶ Run, then open the sheet → Pack → sign in with your email"
