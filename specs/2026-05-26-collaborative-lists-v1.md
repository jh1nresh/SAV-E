# Collaborative Lists v1

## Problem

SAV-E can save places and preview shared trip links, but it does not yet support the social planning loop users expect before a trip: create a named list, add saved places or unsaved map candidates, share the list, let a friend preview it without installing the app, and let that friend save interesting places into their own SAV-E.

## Goal

Add a native SwiftUI collaborative-list MVP that keeps SAV-E memory-first:

- lists are collections of confirmed Map Stamps and explicit unsaved map candidates;
- map POIs stay background until a user adds them;
- shared links are SAV-E links, not Apple Maps links;
- App Clip can preview a list;
- the drawer can plan an itinerary from a selected list.

## Acceptance Criteria

1. User can create a list with a title and optional note.
2. User can add a saved place to a list from the saved place detail surface.
3. User can add an unsaved map candidate to a list from the unsaved candidate detail surface without automatically saving it as a Map Stamp.
4. User can open a drawer list surface that shows owned/joined lists and list contents.
5. User can share a SAV-E list link.
6. A shared list link carries viewer/editor role intent:
   - viewer can preview and save places into their own SAV-E;
   - editor can add their own places after joining.
7. App Clip can preview list links at `https://wanderly.app/list?d=<base64>`.
8. Full app can open/join list links from `https://wanderly.app/list?...` or `wanderly://list?...`.
9. Friend can save list items into their own SAV-E as regular Map Stamps.
10. Drawer can plan an itinerary from a list by using the list items as the route/filter scope.

## Non-Goals

- No realtime multiplayer cursor or conflict resolution.
- No production invite ACL backend in this PR.
- No public social feed, friend graph, referral rewards, or trending surfaces.
- No automatic saving of unsaved map candidates.

## Data Contract

`SaveCollaborativeList`:

- `id`
- `title`
- `note`
- `ownerDisplayName`
- `viewerRole`: owner, editor, viewer
- `items`: saved place or unsaved map candidate snapshots
- `createdAt`
- `updatedAt`

`SaveListItem`:

- `id`
- `source`: savedPlace or mapCandidate
- place name/address/category/coordinates/photos/source/rating snapshot
- `addedByDisplayName`
- `addedAt`

## Sharing

The first version uses encoded public links:

```text
https://wanderly.app/list?d=<base64 SaveSharedListPayload>&r=viewer|editor
wanderly://list?d=<base64 SaveSharedListPayload>&r=viewer|editor
```

This is intentionally compatible with the current trip-share pattern. Backend-backed short links can replace the payload later without changing the drawer/App Clip contract.

## UI Contract

- Drawer quick actions adds `Lists`.
- Lists surface supports create, select, share viewer link, share editor link, and plan from list.
- Place detail card gets `Add to list`.
- Unsaved map candidate card gets `Add to list`; this preserves Map clue and does not save the candidate.
- Joined list detail shows role and whether each item is already in user's SAV-E.
- App Clip list preview shows map, list title, role, item cards, `Open in SAV-E`, and `Save to my SAV-E` intent copy.

## Verification

- Unit tests for list creation, adding saved place, adding unsaved candidate, role-based join, encoded link round trip, and itinerary route action.
- Xcode targeted tests:

```bash
xcodebuild test -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:WanderlyTests/SaveCollaborativeListTests CODE_SIGNING_ALLOWED=NO
```

- Simulator build:

```bash
xcodebuild build -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' CODE_SIGNING_ALLOWED=NO
```
