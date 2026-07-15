# SAV-E iOS

SAV-E is a private place-memory app for iOS. It turns messy travel and food clues — Instagram links, Threads posts, Xiaohongshu URLs, Google Maps links, web pages, voice/text commands, and Google Takeout exports — into confirmed **Map Stamps** with evidence receipts.

Current app version in this repo: **1.0.0 (build 81)**.

## Current product shape

SAV-E is no longer a generic map/list/trip app. The current app is:

```text
source clue → Review receipt → confirmed Map Stamp → private passport / shareable proof / plan
```

The core judgment is conservative: SAV-E should not pretend a clue is a real place until the source, caption/OCR, public search, map match, or user decision gives enough evidence. Uncertain clues stay in **Review** with receipts and next actions.

## What ships in the iOS app

- **Map-first home** — the app opens on confirmed Map Stamps with current-location controls; unresolved links and place clues remain available in Memory Inbox as a secondary review surface.
- **AI command drawer** — persistent bottom drawer for search, “plan around this”, order/recommendation analysis, URL import, voice input, and place actions.
- **Review inbox** — imported social/web clues become review candidates with evidence, rejected evidence, confidence, and source-recovery receipts before saving.
- **Map Stamps** — confirmed places support categories, visibility, detail cards, source links, notes, navigation, deletion, and list membership.
- **Place recovery pipeline** — deterministic parser + public source-search fallback for Instagram/Threads/Xiaohongshu/web clues. Source-only clues remain source-only instead of creating fake places.
- **Google Takeout import** — bulk import saved Google Maps places into reviewable drafts with duplicate handling.
- **Collaborative lists** — create lists, add places, share viewer/editor list links, join list links, and plan from list items.
- **Referral/friends layer** — referral/profile links can hand off starter map packs and complete follow intent after install/open.
- **Passport profile** — profile, language controls, visibility settings, stamp counts, waiting clues, and receipt-style progress surfaces.
- **App Intents / shortcuts** — local app intents for saving a URL and asking SAV-E memory.
- **Bilingual UI path** — English and Traditional Chinese app-language settings for user-visible surfaces.

## Companion surfaces

- **Share Extension** (`SAVEShareExtension`) accepts URLs/text from other apps and queues review candidates.
- **App Clip** (`SAVEClip`) previews SAV-E place links and private/share links on `sav-e-app.vercel.app` when Apple App Clip Experience + Associated Domains are configured.
- **Web fallback** (`save-rn/`) serves public share previews, referral/list routes, and Apple association files through Vercel.
- **Railway backend** (`backend/`) stores places/profiles/receipts/share links, verifies Privy auth, resolves short links, runs source recovery, and powers Sendblue/SLL-R experiments.
- **iMessage extension** (`SAVEiMessageExtension`) exists as a parked spike. It is not embedded in shipping builds until icons and validation are complete.

## Current non-goals / boundaries

- Do not direct-save weak social metadata as a real place.
- Do not configure `wanderly.app` for Universal Links/App Clips until its AASA endpoint returns raw Apple association JSON without Cloudflare/WAF challenge responses.
- Do not ship `GEMINI_API_KEY` in app bundles. Gemini is a backend secret; client-side Gemini is private-development only.
- Do not treat the iMessage target as production until it has app icons, reviewable UX, and validated build settings.
- Full trip import, full referral App Clip profile previews, and production paywall/credits are not the current TestFlight boundary unless a later PR explicitly lands them.

## Tech stack

| Layer | Stack |
|---|---|
| iOS app | SwiftUI, MapKit, App Intents, Speech/AVFoundation voice input |
| Auth | Privy iOS SDK |
| Backend | Railway Node/TypeScript API + Railway Postgres |
| Place intelligence | Deterministic parsers, Google Places API, Gemini via backend, public source recovery |
| Share surfaces | iOS Share Extension, App Clip, Expo/React Native web fallback |
| Web | Expo 54 / React Native Web / Vercel |
| Tests | Swift unit/UI tests, Node backend tests, parser fixture scripts |

## Repository structure

```text
SAV-E/                       SwiftUI iOS app
├── App/                     App entry, auth/onboarding/link handling
├── Views/                   Map, drawer, review, profile, import, trips, shared UI
├── Models/                  Places, review candidates, lists, guides, social/referral models
├── ViewModels/              Map, drawer, profile, trip state
├── Services/                Parsing, search, persistence, local vault, AI, imports, location
├── Intents/                 App Shortcuts / App Intents
└── Resources/               Assets + local Secrets.plist template

SAV-EShareExtension/         iOS share extension target
SAV-EClip/                   App Clip target
SAV-EShared/                 Shared parsers/config used by app, clip, extension
SAV-EiMessage/               Parked iMessage extension spike
backend/                     Railway TypeScript API + Postgres schema/tests
save-rn/                     Expo web fallback for share/referral/list routes
Tests/                       Swift unit and UI tests
scripts/                     Build, config, parser, and fixture checks
project.yml                  XcodeGen project definition
```

## Setup

### 1. Clone

```bash
git clone https://github.com/JhiNResH/SAV-E.git
cd SAV-E
```

### 2. Bootstrap local secrets

```bash
cp -n SAV-E/Resources/Secrets.plist.template SAV-E/Resources/Secrets.plist
cp -n SAV-EShareExtension/Secrets.plist.template SAV-EShareExtension/Secrets.plist
```

Xcode also creates these local files from templates during build if they are missing. It does not overwrite existing `Secrets.plist` files; when templates change, compare manually and add new keys.

Fill local values in `SAV-E/Resources/Secrets.plist` and `SAV-EShareExtension/Secrets.plist`:

| Key | Purpose |
|---|---|
| `GOOGLE_PLACES_API_KEY` | Google Places lookup/details |
| `SAVE_API_URL` | Railway backend URL, currently `https://wanderly-api-production.up.railway.app` |
| `SAVE_PLACE_SHARE_BASE_URL` | Place share route, currently `https://sav-e-app.vercel.app/p` |
| `SAVE_TRIP_SHARE_BASE_URL` | Trip share route, currently `https://sav-e-app.vercel.app/trip` |
| `SAVE_SHARE_BASE_URL` | Legacy trip fallback, currently `https://sav-e-app.vercel.app/trip` |
| `SAVE_LIST_SHARE_BASE_URL` | Collaborative list route, currently `https://sav-e-app.vercel.app/list` |
| `PRIVY_APP_ID` | Privy Dashboard → App Settings → Basics |
| `PRIVY_APP_CLIENT_ID` | Privy iOS client. Must allow bundle id `com.wanderly.app` and URL scheme `wanderly`. |

The app still reads legacy `WANDERLY_*` keys as a migration fallback for older local secrets, but new production config should use `SAVE_*` keys.

Keep real values out of commits.

### 3. Install backend dependencies

```bash
cd backend
npm install
npm run build
```

Railway service variables include:

```bash
DATABASE_URL=${{Postgres.DATABASE_URL}}
PRIVY_APP_ID=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
PRIVY_APP_SECRET=...                 # needed for Privy user provisioning flows
SAVE_GUEST_SESSION_SECRET=...        # stable guest sessions across restarts
GEMINI_API_KEY=...                   # backend-only AI parsing/analysis
GOOGLE_PLACES_API_KEY=...            # backend source recovery / place enrichment
```

Apply/update the schema against Railway Postgres when migrations/schema change:

```bash
psql "$DATABASE_URL" -f backend/sql/schema.sql
```

### 4. Generate and open the Xcode project

```bash
xcodegen generate
open SAV-E.xcodeproj
```

Use the **SAV-E** scheme for the shipping app. The app target is named `SAVE`; bundle IDs stay under `com.wanderly.*` for production compatibility.

## Local verification

### iOS simulator build

Use the wrapper so benign locked-device discovery warnings do not bury the real build output:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Swift tests

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### Backend tests

```bash
cd backend
npm test
```

### Web fallback checks

```bash
cd save-rn
npm install
npm run check:import-links
npm run check:save-cards
npm run check:save-actions
npm run export:web
```

### Focused parser / fixture scripts

```bash
swift scripts/social_place_regression.swift
swift scripts/check-social-link-parser.swift
swift scripts/check-social-ocr-fixtures.swift
swift scripts/check-social-places-refine-fixtures.swift
```

## TestFlight archive

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

Prepare App Store Connect upload options. The generated options are external-TestFlight ready by default. Set `TESTFLIGHT_SCOPE=internal` only for internal-only review builds.

```bash
APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh
TESTFLIGHT_SCOPE=internal APPLE_TEAM_ID="$APPLE_TEAM_ID" scripts/prepare-testflight-export-options.sh build/ExportOptions.TestFlight.Internal.plist
```

Upload:

```bash
xcodebuild \
  -exportArchive \
  -archivePath "$PWD/build/SAV-E.xcarchive" \
  -exportPath "$PWD/build/TestFlightUpload" \
  -exportOptionsPlist "$PWD/build/ExportOptions.TestFlight.plist" \
  -allowProvisioningUpdates \
  APPLE_TEAM_ID="$APPLE_TEAM_ID"
```

## First TestFlight boundary

Ship the native iOS app, Share Extension, and embedded App Clip for SAV-E share links.

Before upload:

- register App IDs for `com.wanderly.app`, `com.wanderly.app.ShareExtension`, and `com.wanderly.app.Clip`
- enable App Group `group.com.wanderly.app` for app and Share Extension
- configure signing team/profiles in Xcode or release xcconfig
- confirm App Store icon and privacy manifest are included
- keep real API keys out of commits and restrict bundled keys where provider dashboards allow it

These Apple identifiers are the existing production compatibility layer. User-facing naming, target display names, release config keys, and share URLs should use SAV-E / SAVE naming.

## Share, App Clip, and Universal Link routes

SAV-E separates share actions from map actions:

- Share = SAV-E link
- Maps = Apple Maps / Google Maps link

Production host: `sav-e-app.vercel.app`.

Current public route shapes:

```text
/p/{shortCode}
/p/{base64urlSharedPlaceDataJson}     # legacy readable
/trip/{base64urlSharedTripDataJson}
/list?d={base64SharedListPayloadJson}&r={viewer|editor}
/r/{code}
/u/{handle}?ref={code}
/my/{signedToken}
```

The full app handles installed-app Universal Links and `wanderly://` deep links. The App Clip target can preview SAV-E place payloads and private/share cards. Full trip import, full list previews, and full referral previews are later surfaces unless a newer release explicitly changes that boundary.

For build 81 / first App Review:

- keep `applinks:sav-e-app.vercel.app` in the app entitlement
- keep `appclips:sav-e-app.vercel.app` in the App Clip entitlement
- keep `appclips:sav-e-app.vercel.app` and `com.apple.developer.associated-appclip-app-identifiers` in the main app entitlement
- set `APPLE_TEAM_ID` in Vercel so `npm run export:web` writes the real `/.well-known/apple-app-site-association`
- set `APPLE_APP_STORE_ID` and `APP_CLIP_BUNDLE_ID` for the Smart App Banner meta written by `save-rn/scripts/patch-web-bundle.js`
- disable bot challenges/WAF rules for `https://sav-e-app.vercel.app/p*`, `https://sav-e-app.vercel.app/r*`, and `https://sav-e-app.vercel.app/.well-known/apple-app-site-association`
- configure App Store Connect App Clip Experiences on `sav-e-app.vercel.app` only
- avoid `wanderly.app` until `https://wanderly.app/.well-known/apple-app-site-association` returns Apple association JSON without a challenge page

Without those Apple/domain steps, the same URL still opens the web app, but iOS will not invoke the App Clip.

## Design direction

SAV-E should feel like a warm private travel notebook, not a generic data table:

| Token | Light | Dark |
|---|---|---|
| Background | `#FFF8F0` cream | `#1C1C1E` charcoal |
| Accent | `#C75B39` terracotta | `#E8A87C` amber |
| Secondary | `#A8B5A0` sage | `#A8B5A0` sage |
| Text | `#2C2C2E` charcoal | `#FFFFFF` |
| Radius | 16–32 px depending on surface | 16–32 px |
| Font | SF Pro | SF Pro |

UX rule: show the receipt behind a recommendation, but keep the main action simple — “what should I do next?”

## License

Private — All rights reserved.
