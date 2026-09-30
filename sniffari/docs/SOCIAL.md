# Pack: live walk sharing — setup

What it does: sign in with an email code, name your dog, invite friends' dogs by code, and when you
start a walk choose **Private / Pack / Pack + their friends**. Your pack gets "🐕 Ricky is walking",
sees your dog's live dot, and "Ricky's walk ended" when you finish.

Privacy, enforced by the database (tested in `supabase/tests`):
- Dogs are the identity. No owner name is stored or shown anywhere.
- Walks are visible only to your pack, or also to their friends if you pick that for the walk. Never to strangers.
- Your live position isn't published within 150 m of your start or finish, and that part of the route is never shared.
- Only the neighbourhood/town is shared as the walk's place. Walks end when you finish and expire on their own (max 4 h).

## One-time setup (~20 min)

### 1. Supabase project
1. <https://supabase.com> → New project (free tier). Region: US East.
2. **SQL Editor** → paste all of `supabase/migrations/20260930000000_social.sql` → Run.
3. **Authentication → Providers → Email**: enabled. **Authentication → Email Templates → Magic Link**: make the body
   include the code, e.g. `Your Sniffari code: {{ .Token }}` (the app asks for the 6-digit code, not a link).
4. **Project Settings → API**: copy the Project URL and the `anon` public key into `sniffari/.env.local`
   (see `.env.local.example`). The anon key is safe in the app; never put the `service_role` key in the app or repo.

### 2. Push notifications (Apple Developer account)
1. <https://developer.apple.com/account/resources/authkeys/list> → **+** → name "Sniffari APNs", tick
   **Apple Push Notifications service (APNs)** → Continue → Register → **Download** the `.p8` (only downloadable once).
   Note the **Key ID**, and your **Team ID** (top right of the developer site).
2. Install the Supabase CLI (`brew install supabase/tap/supabase`), then from `sniffari/`:

```sh
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase secrets set APNS_KEY="$(cat ~/Downloads/AuthKey_XXXXXXXXXX.p8)" APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY APNS_BUNDLE_ID=work.kushman.sniffari APNS_SANDBOX=true
supabase functions deploy notify-walk
```

   `APNS_SANDBOX=true` is for builds installed from Xcode. For TestFlight builds: `supabase secrets unset APNS_SANDBOX`.
   Use the same bundle ID as in Xcode.
3. Xcode → App target → **Signing & Capabilities**: if "Push Notifications" isn't listed, click **+ Capability → Push Notifications**
   (the entitlements file is already in the project).

### 3. Rebuild the app

```sh
cd ~/sniffari-work/sniffari && git pull && npm install && npm run ios:sync
```

Then ▶ Run. Open the sheet → **Pack** → enter your email → code → Ricky. Invite a friend: **Invite a dog** → share the code;
they enter it under "Got a code?".

## Tests

```sh
bash supabase/tests/run.sh   # spins up local Postgres, applies the migration, checks every privacy rule
npm test                     # includes the notification text + APNs signing
```

## Not yet
- Sharing while the phone is locked needs background location (iOS "Always" permission + background mode). For now keep
  Sniffari open during a shared walk (it keeps the screen awake while navigating).
- Sign in with Apple, dog photos, blocking/reporting, community groups (e.g. a local subreddit's circle).
