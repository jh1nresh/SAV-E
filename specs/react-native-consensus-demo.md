# React Native Consensus Demo

## Goal

Ship a React Native version of Wanderly that is good enough for in-person testing at Consensus on 2026-05-04.

This is a demo app, not a full parity rewrite of the native iOS product.

## Scope

- Create a new Expo-based React Native app under `wanderly-rn/`.
- Use local data plus imported links for places and trips so the app works without Privy auth.
- Support three core flows:
  - import a place or event link into saved bookmarks
  - browse saved places
  - build a trip from saved bookmarks
  - generate a Wanderly trip link and hand off the next stop to Tesla
- Reuse the existing shared-trip payload shape so links stay compatible with Wanderly's `?d=<base64>` format.

## Non-Goals

- No Privy React Native auth in this pass.
- No cross-app Share Extension rewrite.
- No App Clip equivalent.
- No backend write path to Railway for this pass.
- No map SDK integration unless it is trivial; list-first is acceptable for the demo.

## Product Shape

The RN demo should have three tabs:

1. `Places`
   - paste a supported place or event link
   - import directly from clipboard
   - save the parsed result into bookmarks
   - if the link is an event, refine it into a venue-like stop before saving
   - list seeded places plus imported bookmarks
   - filter by category
   - add/remove places from the active draft trip

2. `Trip`
   - show selected stops
   - reorder not required for v1
   - create trip link using the same base64 JSON structure as `SharedTripData`
   - share trip link
   - trip planning starts from saved bookmarks, matching the native Wanderly model

3. `Share`
   - show a more polished handoff summary for the current trip
   - decode and preview the generated trip payload locally
   - `Send Next Stop to Tesla` button using Apple Maps URL share

## Technical Direction

- Expo app with TypeScript.
- Local state only.
- Persist bookmarks locally on-device.
- Use clipboard import for fast mobile testing.
- Keep code self-contained and readable.
- Use a clean mobile-first UI with a Wanderly-like warm palette.

## Acceptance Criteria

- `npm install` succeeds in `wanderly-rn/`.
- `npx expo start` launches the app.
- User can:
  - open the app in Expo Go
  - paste a supported link and save it into bookmarks
  - import a link from the clipboard in one tap
  - refine event links into a plausible venue / stop before saving
  - select bookmarked places
  - create a trip link
  - share the next stop to Tesla via Apple Maps URL
- Trip payload matches Wanderly's existing `SharedTripData` fields:
  - `name`
  - `city`
  - `stops[]` with `id`, `name`, `address`, `lat`, `lng`, `time`, `note`

## Follow-up

- If the demo lands well, phase 2 should evaluate:
  - Privy React Native auth
  - Railway-backed persistence
  - native share ingestion on Android/iOS
