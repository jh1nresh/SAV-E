# Wanderly iOS

AI-powered place discovery and trip planning app for iOS.

Save places from links shared from Instagram, Threads, Xiaohongshu, Maps, or the web — Wanderly extracts place details and pins them on your personal map. Plan trips, optimize routes, and track your adventures.

## Features

- **Map View** — MapKit with custom category-colored pins, clustering, and bottom sheet details
- **Place List** — Filterable (Want to Go / Visited / All), sortable (Nearest / Recent / Rating), swipe actions
- **Trip Planner** — City selector, timeline view, drag-to-reorder, AI route optimization
- **Share Extension** — Accept URLs and text from other apps, parse, and save to map
- **Profile** — Stats, world map visualization, collections, subscription management
- **Onboarding** — 3-step carousel
- **Place Detail** — Photo carousel, info grid, notes, navigate button, source link
- **App Clip** — Target exists for shared trip links, but first TestFlight/App Store submission should ship native iOS + Share Extension first

## Tech Stack

- **SwiftUI** + **MapKit** for UI
- **Privy iOS SDK** for auth (Sign in with Apple / Google / Email + embedded wallet)
- **Railway Node API + Railway Postgres** for backend persistence
- **Gemini API** for AI content parsing
- **Google Places API** for place matching and details
- **App Clip** target for shareable trip links, deferred until Associated Domains, AASA, and App Clip Experience setup are complete
- **Share Extension** target for cross-app saving

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/JhiNResH/wanderly.git
   cd wanderly
   ```

2. Fill in your local API keys in `Wanderly/Resources/Secrets.plist` and `WanderlyShareExtension/Secrets.plist`:
   - `GEMINI_API_KEY` — from Google AI Studio
   - `GOOGLE_PLACES_API_KEY` — from [Google Cloud Console](https://console.cloud.google.com/)
   - `WANDERLY_API_URL` — Railway backend service URL
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

6. Build and run on simulator or device.

## First TestFlight Boundary

Ship the native iOS app and Share Extension first. The App Clip target is kept in the project, but should not be treated as review-ready until `wanderly.app` associated domains, the Apple App Site Association file, and an App Clip Experience are configured in App Store Connect.

Before uploading a build:

- register App IDs for `com.wanderly.app`, `com.wanderly.app.ShareExtension`, and later `com.wanderly.app.Clip`
- enable the App Group `group.com.wanderly.app` for the app and Share Extension
- configure signing team/profiles in Xcode or release xcconfig
- confirm the App Store icon and privacy manifest are included
- keep real API keys out of commits and restrict bundled keys where provider dashboards allow it

## App Clip Trip Links

Wanderly trip links use this shape:

```text
https://wanderly.app/trip?d=<base64-url-encoded SharedTripData JSON>
```

The App Clip target can preview this payload and pass it to the full app through `wanderly://trip?d=...`. The full app also handles the same `https://wanderly.app/trip?...` universal link when installed.

Before this works for friends without the full app installed:

- enable Associated Domains on `com.wanderly.app` and `com.wanderly.app.Clip` in Apple Developer
- keep `applinks:wanderly.app` and `appclips:wanderly.app` in the app entitlement
- keep `appclips:wanderly.app` in the App Clip entitlement
- set `APPLE_TEAM_ID` in the Vercel build environment so `npm run export:web` writes the real `/.well-known/apple-app-site-association`
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
