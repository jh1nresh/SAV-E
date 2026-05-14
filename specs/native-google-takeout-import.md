# Native Google Takeout Import

## Goal

Let native iOS users import their existing Google Maps saved places from Google Takeout files without creating fake pins.

## Scope

- Support file picker imports for `.zip`, `.json`, `.geojson`, and `.kml`.
- Parse Google Takeout-like place exports locally on device.
- Preview parsed places before saving.
- Save only entries with reliable coordinates into existing Railway/Postgres-backed places.
- Deduplicate against existing saved places and within the imported batch.
- Keep entries without reliable coordinates in the preview as review drafts.

## Acceptance Criteria

- The AI drawer exposes an Import action.
- Import opens a native file picker for `.zip`, `.json`, `.geojson`, and `.kml`.
- Parsed entries are split into Ready to save and Needs review.
- Needs review entries are not saved as map pins.
- Saving selected ready entries calls the existing backend persistence path.
- Duplicate entries are skipped.
- The app builds with `xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -configuration Debug -destination 'generic/platform=iOS' build`.

## Out of Scope

- Google OAuth or automatic Google Maps sync.
- Server-side Takeout processing.
- Persisted review-draft queue.
- Geocoding entries that do not already include reliable coordinates.
