# Local SAV-E Vault and App Intents

## Problem

SAV-E currently treats place extraction as the main success path. If a social URL
cannot become a reliable place or review candidate, the original source can feel
lost. That weakens the product thesis that SAV-E is a personal-agent memory
skill rather than only a map app.

## Goal

Add a first local-first memory layer and Siri/Shortcuts entry points:

```text
source URL / text
-> local App Group vault
-> source_only / review_candidate / confirmed_place state
-> later agent-readable queries
```

## Scope

- Add `SaveMemoryRecord` as the local vault record model.
- Add `SaveLocalVaultService` backed by an App Group JSON file.
- Add `SavePlaceFromURLIntent` for Siri/Shortcuts source capture.
- Add `AskSaveMemoryIntent` for a lightweight recent-memory answer.
- Add `SAVEAppShortcuts` so Shortcuts/Siri can discover the actions.
- Write pending review candidates into the local vault when the main app imports
  shared candidates.
- Add a small profile debug view for recent vault records.

## Acceptance Criteria

- A Shortcut/App Intent can save a URL into local memory without opening the app.
- Asking SAV-E memory returns a short summary of recent local records.
- Shared review candidates are mirrored into local vault as `review_candidate`.
- The UI exposes recent vault records for debugging.
- No unreliable social URL becomes a confirmed map pin.

## Out of Scope

- CryptoKit encryption.
- SQLite migration.
- Mac local agent bridge.
- Dojo workflow receipts.
- Signed place cards.
- Cloud sync for local vault records.

## Verification

```bash
xcodegen generate
xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
cd save-rn && npm run check:import-links && npx tsc --noEmit
git diff --check
```
