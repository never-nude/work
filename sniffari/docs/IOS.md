# Sniffari on iPhone

The app is the same web app wrapped by Capacitor (`ios/`). You need a Mac with Xcode.

## Tonight: run it on your phone over USB (free Apple ID is enough)

```sh
cd ~/sniffari-work/sniffari && git pull && npm install && npm run ios
```

That builds the web app, copies it into the Xcode project and opens Xcode. Then:

1. Plug in the iPhone (unlock it; tap **Trust** if asked).
2. In Xcode, click **App** in the left sidebar → **Signing & Capabilities** tab → **Team**: pick your Apple ID
   (Xcode → Settings → Accounts → + to add it if the list is empty).
   If Xcode complains the bundle ID is taken, change `work.kushman.sniffari` to something unique like `com.<yourname>.sniffari`.
3. At the top of the window, pick your iPhone as the run destination, then press **▶ Run**.
4. First launch only, on the phone: Settings → General → VPN & Device Management → your Apple ID → **Trust**.
   (iPhone also needs Developer Mode: Settings → Privacy & Security → Developer Mode → On, then restart.)
5. Open Sniffari, allow location "While Using the App".

A free Apple ID install expires after 7 days — press Run again to refresh it.

## TestFlight (needs the paid Apple Developer Program, $99/yr)

1. <https://appstoreconnect.apple.com> → Apps → **+** → New App: iOS, name "Sniffari", bundle ID = the one in Xcode.
2. In Xcode: destination **Any iOS Device (arm64)** → **Product → Archive**.
3. Organizer window → **Distribute App** → **App Store Connect** → Upload.
4. After processing (~10–30 min), App Store Connect → the app → **TestFlight** → add yourself as an internal tester.
   Install the TestFlight app on the phone and accept.

Bump the build number (App target → General → Build) for every upload.

## After changing code

```sh
npm run ios:sync      # rebuild + copy into Xcode; then ▶ Run in Xcode
```

## App icon

A placeholder icon ships in `ios/App/App/Assets.xcassets/AppIcon.appiconset/`. To use the real artwork, save it as a
1024×1024 PNG **without transparency** at `assets/icon.png`, then:

```sh
npx @capacitor/assets generate --ios --iconBackgroundColor '#16131c'
```

## Notes

- Location permission text lives in `ios/App/App/Info.plist` (`NSLocationWhenInUseUsageDescription`).
- Map data (OpenStreetMap / Overpass), elevation and geocoding are fetched live over the network and cached on the phone
  for 7 days, so the first load of a new area takes a little while.
- Fixtures (`?fixture=…`) are dev-only; the app starts on live data at your location.
