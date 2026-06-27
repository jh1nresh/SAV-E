# SAV-E iOS

Private place-memory app for iOS.

Save places from links shared from Instagram, Threads, Xiaohongshu, Maps, or the web. SAV-E keeps uncertain places in Review first, then turns confirmed places into private Map Stamps.

## Features

- **Map View** — MapKit with custom category-colored pins, clustering, and bottom sheet details
- **Place List** — Filterable (Want to Go / Visited / All), sortable (Nearest / Recent / Rating), swipe actions
- **Share Extension** — Accept URLs and text from other apps, parse them into Review, and save confirmed places to the map
- **Profile** — Stats, world map visualization, collections, subscription management
- **Onboarding** — 3-step carousel
- **Place Detail** — Photo carousel, info grid, notes, navigate button, source link
- **Second-wave surfaces** — Google Takeout import, collaborative lists, and full trip import stay out of the first public-test gate

## Tech Stack

- **SwiftUI** + **MapKit** for UI
- **Privy iOS SDK** for auth (Sign in with Apple / Google / Email + embedded wallet)
- **Railway Node API + Railway Postgres** for backend persistence
- **Gemini API** for AI content parsing
- **Google Places API** for place matching and details
- **App Clip** target embedded in the iOS app for shareable-link previews once App Store Connect App Clip Experiences are configured
- **Share Extension** target for cross-app saving

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/JhiNResH/SAV-E.git
   cd SAV-E
   ```

2. Bootstrap local secrets:
   ```bash
   cp -n SAV-E/Resources/Secrets.plist.template SAV-E/Resources/Secrets.plist
   cp -n SAV-EShareExtension/Secrets.plist.template SAV-EShareExtension/Secrets.plist
   ```

   Xcode also creates these local files from the templates during build if they are missing. It does not overwrite existing local `Secrets.plist` files; when templates change, compare them manually and add any new keys to your local files. Fill in your local API keys in `SAV-E/Resources/Secrets.plist` and `SAV-EShareExtension/Secrets.plist`:
   - `GOOGLE_PLACES_API_KEY` — from [Google Cloud Console](https://console.cloud.google.com/)
   - `SAVE_API_URL` — Railway backend service URL, currently `https://wanderly-api-production.up.railway.app`
   - `SAVE_PLACE_SHARE_BASE_URL` — production place share route, currently `https://sav-e-app.vercel.app/p`
   - `SAVE_TRIP_SHARE_BASE_URL` — production trip share route, currently `https://sav-e-app.vercel.app/trip`
   - `SAVE_SHARE_BASE_URL` — legacy trip share route fallback, currently `https://sav-e-app.vercel.app/trip`
   - `SAVE_LIST_SHARE_BASE_URL` — production collaborative list share route, currently `https://sav-e-app.vercel.app/list`
   - `PRIVY_APP_ID` — from Privy Dashboard → App Settings → Basics
   - `PRIVY_APP_CLIENT_ID` — from Privy Dashboard → App Settings → Clients. The iOS app client must allow bundle id `com.wanderly.app` and URL scheme `wanderly`.
   - `GEMINI_API_KEY` is a backend secret. Do not ship it in app `Secrets.plist`; only set `SAVE_ALLOW_CLIENT_GEMINI=true` with a local Gemini key for private development.

   New production config should use the `SAVE_*` keys above. The app still reads legacy `WANDERLY_*` keys as a migration fallback when present in an older local `Secrets.plist`, but the templates and release docs are SAV-E-first.
   - Keep real values out of commits.

3. Configure the Railway backend:
   ```bash
   cd backend
   npm install
   npm run build
   ```

   Railway service variables:
   ```bash
   DATABASE_URL=${{Postgres.DATABASE_URL}}
   PRIVY_APP_ID=...
   PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
   ```

   Apply the schema to Railway Postgres:
   ```bash
   psql "$DATABASE_URL" -f sql/schema.sql
   ```

4. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

5. Open the project in Xcode:
   ```bash
   open SAV-E.xcodeproj
   ```

6. Build and run on simulator or device. Simulator builds do not need signing; device builds and archives require either passing `APPLE_TEAM_ID` through the CLI or selecting your Apple Developer Team in Xcode locally.

For local simulator verification, use the wrapper so Xcode's benign locked-device discovery warnings do not bury the real build output:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=53A8DA29-D4F6-43AF-A81E-47929D1DF97D' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## TestFlight Archive

Set `APPLE_TEAM_ID` to the 10-character Apple Developer Team ID for the account that owns the App IDs. XcodeGen passes it into all iOS targets as `DEVELOPMENT_TEAM`.

```bash
export APPLE_TEAM_ID=ABCDE12345
xcodegen generate
xcodebuild \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/SAV-E.xcarchive" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  archive
```

Prepare an App Store Connect upload options plist. The generated options are external-TestFlight ready by default. Set `TESTFLIGHT_SCOPE=internal` only when producing an internal-only review build.

```bash
APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh
TESTFLIGHT_SCOPE=internal APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh build/ExportOptions.TestFlight.Internal.plist
```

Upload the archive to App Store Connect for TestFlight processing:

```bash
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/SAV-E.xcarchive" \
  -exportPath "$PWD/build/TestFlightUpload" \
  -exportOptionsPlist "$PWD/build/ExportOptions.TestFlight.plist" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID"
```

## First TestFlight Boundary

Ship the native iOS app, Share Extension, and embedded App Clip for SAV-E share links. App Clip invocation still depends on Apple Developer associated-domain capabilities, the production AASA file, App Store Connect App Clip Experiences, and Apple's associated-domain CDN.

Before uploading a build:

- register App IDs for `com.wanderly.app`, `com.wanderly.app.ShareExtension`, and `com.wanderly.app.Clip`
- enable the App Group `group.com.wanderly.app` for the app and Share Extension

These Apple identifiers are the existing production compatibility layer. The user-facing product, Xcode targets, release config keys, and share URLs should use SAV-E / SAVE naming.
- configure signing team/profiles in Xcode or release xcconfig
- confirm the App Store icon and privacy manifest are included
- keep real API keys out of commits and restrict bundled keys where provider dashboards allow it

## App Clip Share Routes

App Clip support is enabled for SAV-E share links. If the full app is installed, Universal Links should open the app. If the full app is not installed and the App Clip Experience is configured in App Store Connect, iOS should show the App Clip card instead of relying on the web fallback.

SAV-E separates share actions from map actions:

- Share = SAV-E link
- Maps = Apple Maps link

SAV-E place links use this shape:

```text
https://sav-e-app.vercel.app/p/<shortCode>
```

New place links should use backend-created short codes. The backend resolver
returns the public `SharedPlaceData` payload for the App Clip, full app, and web
preview. Legacy embedded-payload links remain readable:

```text
https://sav-e-app.vercel.app/p/<base64-url-encoded SharedPlaceData JSON>
```

SAV-E trip links use this shape:

```text
https://sav-e-app.vercel.app/trip/<base64-url-encoded SharedTripData JSON>
```

SAV-E collaborative list and referral links use these shapes:

```text
https://sav-e-app.vercel.app/list?d=<base64 SharedListPayload JSON>&r=<viewer|editor>
https://sav-e-app.vercel.app/r/<code>
https://sav-e-app.vercel.app/u/<handle>?ref=<code>
```

Private My SAV-E links use this shape:

```text
https://sav-e-app.vercel.app/my/<signedToken>
```

The App Clip target can preview place payloads with photo, rating, hours, address, source, and save/open actions. It can also preview private My SAV-E links as native saved-place cards, verified visits, and receipt-gated reviews. Full trip import, list previews, and referral previews are still later surfaces. The full app handles `https://sav-e-app.vercel.app/p/...` and `https://sav-e-app.vercel.app/trip/...` links when installed. Legacy `https://wanderly.app/trip?d=...` links remain readable during migration.

Before this works for friends without the full app installed:

- enable Associated Domains on `com.wanderly.app` and `com.wanderly.app.Clip` in Apple Developer
- keep `applinks:sav-e-app.vercel.app` in the app entitlement
- keep `appclips:sav-e-app.vercel.app` in the App Clip entitlement
- keep `appclips:sav-e-app.vercel.app` and `com.apple.developer.associated-appclip-app-identifiers` in the main app entitlement
- set `APPLE_TEAM_ID` in the Vercel build environment so `npm run export:web` writes the real `/.well-known/apple-app-site-association`
- keep `APPLE_APP_STORE_ID` and `APP_CLIP_BUNDLE_ID` configured for the Smart App Banner meta written by `save-rn/scripts/patch-web-bundle.js`
- disable bot challenges/WAF rules for `https://sav-e-app.vercel.app/p*`, `https://sav-e-app.vercel.app/trip*`, `https://sav-e-app.vercel.app/my*`, and `https://sav-e-app.vercel.app/.well-known/apple-app-site-association`; iOS cannot complete App Clip or Universal Link association through an HTML challenge page
- keep App Store Connect App Clip Experiences on `https://sav-e-app.vercel.app/...` routes until `wanderly.app` serves Apple association files without Cloudflare challenge responses
- create App Clip Experiences in App Store Connect for `https://sav-e-app.vercel.app/p`, `https://sav-e-app.vercel.app/trip`, `https://sav-e-app.vercel.app/list`, `https://sav-e-app.vercel.app/r`, `https://sav-e-app.vercel.app/u`, and `https://sav-e-app.vercel.app/my`
- wait for Apple's associated-domain CDN to pick up the AASA file

Without those Apple/domain steps, the same URL still opens the web app, but iOS will not invoke the App Clip. If `APPLE_TEAM_ID` is missing, the web build writes a disabled AASA placeholder with no app IDs so Vercel does not serve the SPA shell as Apple association data.

## Referral Profile Links

SAV-E referral links use these shapes:

```text
https://sav-e-app.vercel.app/r/<code>
https://sav-e-app.vercel.app/u/<handle>?ref=<code>
```

The App Clip preview can later show the referrer's profile, a starter map pack, and a follow CTA. The handoff opens the full app through `wanderly://referral?code=<code>&handle=<handle>&lens=friends`, where the full app stores the referrer and intended follow lens before completing follow after install/open.

Before production referral App Clips work, `sav-e-app.vercel.app` needs the same Apple associated-domain and App Clip Experience setup as `wanderly.app`.

## Project Structure

```
SAV-E/
├── App/                    Main app entry + tab-based root
├── Views/
│   ├── Map/                Map view with annotations
│   ├── List/               Filterable place list with cards
│   ├── Trips/              Trip planner with timeline
│   ├── Profile/            User profile and stats
│   ├── Detail/             Place detail view
│   ├── Onboarding/         3-step onboarding carousel
│   └── Shared/             Reusable components
├── Models/                 Data models (Place, Trip, UserProfile)
├── ViewModels/             MVVM view models
├── Services/               API service protocols + stubs
├── Extensions/             Color theme + utilities
└── Resources/              Assets
SAV-EShareExtension/     Share Extension target
SAV-EClip/               App Clip target
backend/                    Railway API + Postgres schema
```

## Design Theme

| Token              | Light           | Dark            |
|---------------------|-----------------|-----------------|
| Background          | #FFF8F0 (Cream) | #1C1C1E (Charcoal) |
| Accent              | #C75B39 (Terracotta) | #E8A87C (Amber) |
| Secondary           | #A8B5A0 (Sage)  | #A8B5A0 (Sage)  |
| Text                | #2C2C2E (Charcoal) | #FFFFFF         |
| Corner Radius       | 16px            | 16px            |
| Font                | SF Pro (system) | SF Pro (system) |

## Dependencies (Swift Package Manager)

- [privy-io/privy-ios](https://github.com/privy-io/privy-ios) — Authentication
- Railway — Backend hosting + Postgres
- Google Places API — REST via URLSession
- Gemini API — REST via URLSession

## License

Private — All rights reserved.
