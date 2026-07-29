# SAV-E Atlas Trips + Live Map Parity v0

## Problem

The production Trips root still renders the retired scrollable notebook
dashboard. The existing Map parity gate only captures the illustrated
`--uitest-atlas-parity-fixture`; it does not prove that the real MapKit root or
Trip Map uses the approved Atlas shell. Trip Map also renders the Root Map
place card instead of the approved stop card.

## Scope

- Replace Trips root with one fixed-viewport Little Atlas composition backed by
  real `TripPackStore` data and actions.
- Keep MapKit interaction, location, pins, selection, and routes.
- Apply the approved header, muted atlas palette, place/stop card geometry, and
  fixed Root or Trip tab shell to the live map path.
- Add a focused UI regression that opens Trips, Root Map, and Trip Map without
  `--uitest-atlas-parity-fixture`.

## Acceptance

1. Trips has no primary `ScrollView`, shows at most three Trip summaries, opens
   a real Trip, and retains New Trip plus global link capture.
2. Root Map uses the fixed Root tabs and `PlaceAtlasCard`.
3. Trip Map uses the fixed Trip tabs and `TripMapPlaceCard`.
4. Both live maps expose the MapKit surface, current-location control, and the
   correct detail action.
5. Opening a map place detail and dismissing it returns to the originating tab
   shell.
6. Generic iOS Simulator build exits 0.
7. One task-owned headless simulator captures Trips, Root Map, and Trip Map,
   then is shut down and deleted.

## Verification boundary

The existing four-screen raster parity remains unchanged: its illustrated Map
target is a visual-direction fixture. The new live-map UI regression exercises
the production component tree and interaction contract; MapKit tile pixels are
not compared to the illustrated raster.

## Xcode context receipt

- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Deployment target: iOS 17.0
- Iteration destination: `generic/platform=iOS Simulator`
- Final runtime: one task-owned headless iOS simulator for UI screenshots
- DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- Security scan: N/A; presentation, navigation, and UI tests only
- Merge/deploy: excluded
