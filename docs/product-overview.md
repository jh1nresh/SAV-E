# Product overview

[Documentation index](README.md) · [Repository home](../README.md)

Implementation overview moved from the repository README. For state semantics and design authority, see [DESIGN.md](../DESIGN.md). For a particular shipped build, check its release evidence.

## Current product shape

Savvy is no longer a generic map/list/trip app. The current app is:

```text
source clue → Save / Review receipt → confirmed Map Stamp → Home / Map / Plan / Passport
```

The core judgment is conservative: Savvy should not pretend a clue is a real place until the source, caption/OCR, public search, map match, or user decision gives enough evidence. Uncertain clues stay in **Review** with receipts and next actions.

## What ships in the iOS app

- **Five-part app shell** — Home, Map, a raised Save control, Plan, and Passport use a compact Liquid Glass tab bar. Save opens capture without replacing the selected tab.
- **Region-based Home** — confirmed saves are grouped by region and use a stored or enriched place photo when one is available. The denser Saves library remains a child screen rather than a root tab.
- **Map + three-stage search drawer** — the map keeps current-location controls and confirmed Map Stamps while search expands through compact, medium, and large stages for results, review, and place actions.
- **Save capture** — the centre control accepts URLs, pasted text, voice/text commands, and Google Takeout exports, then routes uncertain clues through Review.
- **Plan** — drafts a walking day from confirmed Map Stamps in a chosen city. Unsaved attractions stay labeled as Unsaved Candidates. Arrival and hotel times shrink the day; Savvy does not book flights or rooms.
- **Review inbox** — imported social/web clues become review candidates with evidence, rejected evidence, confidence, and source-recovery receipts before saving.
- **Map Stamps** — confirmed places support categories, visibility, detail cards, source links, notes, navigation, deletion, and list membership.
- **Place recovery pipeline** — deterministic parser + public source-search fallback for Instagram/Threads/Xiaohongshu/web clues. Source-only clues remain source-only instead of creating fake places.
- **Collaborative lists** — create lists, add places, share viewer/editor list links, join list links, and plan from list items.
- **Referral/friends layer** — referral/profile links can hand off starter map packs and complete follow intent after install/open.
- **Passport profile** — profile, language controls, visibility settings, stamp counts, waiting clues, receipt-style progress, and working invite/list share actions.
- **Trips** — saved itineraries remain reachable from Plan and from a place. Plan is the permanent root workbench.
- **App Intents / shortcuts** — local app intents for saving a URL and asking Savvy memory.
- **Bilingual UI path** — English and Traditional Chinese app-language settings for user-visible surfaces.

## Companion surfaces

- **Share Extension** (`SAVEShareExtension`) accepts URLs/text from other apps and queues review candidates.
- **App Clip** (`SAVEClip`) previews Savvy place links and private/share links on `sav-e-app.vercel.app` when Apple App Clip Experience + Associated Domains are configured.
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
| Place intelligence | Deterministic parsers, Google Places API, Gemini through the backend, public source recovery |
| Share surfaces | iOS Share Extension, App Clip, Expo/React Native web fallback |
| Web | Expo 54 / React Native Web / Vercel |
| Tests | Swift unit/UI tests, Node backend tests, parser fixture scripts |
