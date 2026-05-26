# SAV-E iOS

AI-powered place discovery and trip planning app for iOS.

Save places from links shared from Instagram, Threads, Xiaohongshu, Maps, or the web — SAV-E extracts place details and pins them on your personal map. Plan trips, optimize routes, and track your adventures.

## Features

- **Map View** — MapKit with custom category-colored pins, clustering, and bottom sheet details
- **Place List** — Filterable (Want to Go / Visited / All), sortable (Nearest / Recent / Rating), swipe actions
- **Trip Planner** — City selector, timeline view, drag-to-reorder, AI route optimization
- **Share Extension** — Accept URLs and text from other apps, parse, and save to map
- **Profile** — Stats, world map visualization, collections, subscription management
- **Onboarding** — 3-step carousel
- **Place Detail** — Photo carousel, info grid, notes, navigate button, source link
- **App Clip** — Lightweight shared trip preview for `https://wanderly.app/trip?d=...`

## Tech Stack

- **SwiftUI** + **MapKit** for UI
- **Privy iOS SDK** for auth (Sign in with Apple / Google / Email + embedded wallet)
- **Railway Node API + Railway Postgres** for backend persistence
- **Gemini API** for AI content parsing
- **Google Places API** for place matching and details
- **App Clip** target for shareable trip links, including Associated Domains and full-app handoff
- **Share Extension** target for cross-app saving

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/JhiNResH/SAV-E.git
   cd SAV-E
   ```

2. Bootstrap local secrets:
   ```bash
   cp -n Wanderly/Resources/Secrets.plist.template Wanderly/Resources/Secrets.plist
   cp -n WanderlyShareExtension/Secrets.plist.template WanderlyShareExtension/Secrets.plist
   ```

   Xcode also creates these local files from the templates during build if they are missing. It does not overwrite existing local `Secrets.plist` files; when templates change, compare them manually and add any new keys to your local files. Fill in your local API keys in `Wanderly/Resources/Secrets.plist` and `WanderlyShareExtension/Secrets.plist`:
   - `GEMINI_API_KEY` — from Google AI Studio
   - `GOOGLE_PLACES_API_KEY` — from [Google Cloud Console](https://console.cloud.google.com/)
   - `SAVE_API_URL` — Railway backend service URL
   - `SAVE_SHARE_BASE_URL` — production share route, currently `https://wanderly.app/trip`
   - `PRIVY_APP_ID` — from Privy Dashboard → App Settings → Basics
   - `PRIVY_APP_CLIENT_ID` — from Privy Dashboard → App Settings → Clients. The iOS app client must allow bundle id `com.wanderly.app` and URL scheme `wanderly`.
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
   open Wanderly.xcodeproj
   ```

6. Build and run on simulator or device. Simulator builds do not need signing; device builds and archives require either passing `APPLE_TEAM_ID` through the CLI or selecting your Apple Developer Team in Xcode locally.

## TestFlight Archive

Set `APPLE_TEAM_ID` to the 10-character Apple Developer Team ID for the account that owns the App IDs. XcodeGen passes it into all iOS targets as `DEVELOPMENT_TEAM`.

```bash
export APPLE_TEAM_ID=ABCDE12345
xcodegen generate
xcodebuild \
  -project Wanderly.xcodeproj \
  -scheme Wanderly \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/Wanderly.xcarchive" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  archive
```

Prepare an App Store Connect upload options plist. The generated options mark the upload as internal TestFlight only, so use this for early internal review builds rather than external testers or App Store release candidates.

```bash
APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh
```

Upload the archive to App Store Connect for TestFlight processing:

```bash
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/Wanderly.xcarchive" \
  -exportPath "$PWD/build/TestFlightUpload" \
  -exportOptionsPlist "$PWD/build/ExportOptions.TestFlight.plist" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID"
```

## First TestFlight Boundary

Ship the native iOS app, Share Extension, and App Clip together. App Clip readiness requires Apple Developer and App Store Connect setup in addition to the repo configuration:

Before uploading a build:

- register App IDs for `com.wanderly.app`, `com.wanderly.app.ShareExtension`, and `com.wanderly.app.Clip`
- enable the App Group `group.com.wanderly.app` for the app and Share Extension
- enable Associated Domains on `com.wanderly.app` and `com.wanderly.app.Clip`
- enable the App Clip association capability on `com.wanderly.app`
- configure signing team/profiles in Xcode or release xcconfig
- confirm the App Store icon and privacy manifest are included
- keep real API keys out of commits and restrict bundled keys where provider dashboards allow it
- create the App Clip Experience in App Store Connect for `https://wanderly.app/trip`

## App Clip Trip Links

SAV-E trip links use this shape:

```text
https://wanderly.app/trip?d=<base64-url-encoded SharedTripData JSON>
```

The App Clip target can preview this payload and pass it to the full app through `wanderly://trip?d=...`. The full app also handles the same `https://wanderly.app/trip?...` universal link when installed.

Before this works for friends without the full app installed:

- enable Associated Domains on `com.wanderly.app` and `com.wanderly.app.Clip` in Apple Developer
- keep `applinks:wanderly.app` and `appclips:wanderly.app` in the app entitlement
- keep `appclips:wanderly.app` in the App Clip entitlement
- set `APPLE_TEAM_ID` in the Vercel build environment so `npm run export:web` writes the real `/.well-known/apple-app-site-association`
- disable bot challenges/WAF rules for `https://wanderly.app/trip*` and `https://wanderly.app/.well-known/apple-app-site-association`; iOS cannot complete App Clip or Universal Link association through an HTML challenge page
- create the App Clip Experience in App Store Connect for `https://wanderly.app/trip`
- wait for Apple's associated-domain CDN to pick up the AASA file

Without those Apple/domain steps, the same URL still opens the web app, but iOS will not invoke the App Clip. If `APPLE_TEAM_ID` is missing, the web build writes a disabled AASA placeholder with no app IDs so Vercel does not serve the SPA shell as Apple association data.

## Project Structure

```
Wanderly/
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
WanderlyShareExtension/     Share Extension target
WanderlyClip/               App Clip target
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
