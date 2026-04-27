# Wanderly iOS

AI-powered place discovery and trip planning app for iOS.

Save places from Instagram, Threads, Xiaohongshu, or any app — Wanderly's AI extracts place details and pins them on your personal map. Plan trips, optimize routes, and track your adventures.

## Features

- **Map View** — MapKit with custom category-colored pins, clustering, and bottom sheet details
- **Place List** — Filterable (Want to Go / Visited / All), sortable (Nearest / Recent / Rating), swipe actions
- **Trip Planner** — City selector, timeline view, drag-to-reorder, AI route optimization
- **Share Extension** — Accept URLs and images from any app, AI-parse and save to map
- **Profile** — Stats, world map visualization, collections, subscription management
- **Onboarding** — 3-step carousel
- **Place Detail** — Photo carousel, info grid, notes, navigate button, source link
- **App Clip** — Lightweight version for opening shared trip links

## Tech Stack

- **SwiftUI** + **MapKit** for UI
- **Privy iOS SDK** for auth (Sign in with Apple / Google / Email + embedded wallet)
- **Railway Node API + Railway Postgres** for backend persistence
- **Gemini API** for AI content parsing
- **Google Places API** for place matching and details
- **App Clip** target for shareable trip links
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
