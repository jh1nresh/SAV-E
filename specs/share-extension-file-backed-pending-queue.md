# Share Extension File-Backed Pending Queue

SAV-E share extension handoff should not rely on App Group `UserDefaults`
for pending places or pending review candidates. iOS can emit CFPrefs warnings
for app group preferences, and the pending queue is already structured JSON
data that fits the local vault pattern.

## Goal

Move the share extension pending handoff queue to App Group JSON files:

- `pending-places.json`
- `pending-review-candidates.json`

## Acceptance Criteria

- Main app consumes pending places from App Group JSON file storage.
- Main app consumes pending review candidates from App Group JSON file storage.
- Share extension appends pending places to the same App Group JSON file.
- Share extension appends pending review candidates to the same App Group JSON file.
- Failed imports are restored by writing the remaining items back to the file.
- Source-only local memory writes use App Group file storage directly and do not
  require `UserDefaults(suiteName:)`.
- No change to parsing, backend schema, or review candidate UX.

## Verification

- `git diff --check`
- `xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## Out Of Scope

- Backend changes.
- TestFlight upload.
- App Clip storage changes.
- Migration from old `UserDefaults` pending queues.
