# Map photo-pin evidence (DESIGN gate 5)

Prototype component stills and motion recordings are produced on the
macOS CI runner from this SwiftUI code — not from composed HTML.

The live root remains `SaveDoodleMapView`. `SaveMapPhotoPinsRoot` is inactive;
these DEBUG fixtures do not prove production search, routes, Home filters or
photo binding. Frame rate requires inspecting the recorded file, not its name.

## How they are made

1. `SavvyMapPhotoPinSnapshotExport` (`#if DEBUG`) hosts
   `SavvyMapPhotoPinPreviewCatalog` / cells / the P14 board in a window
   (`overrideUserInterfaceStyle` + `ImageRenderer` fallback) so light and
   dark `UIColor` traits actually apply. The catalog snapshot uses
   `snapshotLayout` (no `ScrollView` / `Lazy*`).
2. `SAVETests.testGate5ImageRendererExportWritesLightDarkAndChinese`
   attaches named PNGs as `XCTAttachment`s. CI exports them with
   `xcresulttool`, then `scripts/export-gate5-named-stills.py` copies
   them to `imagerenderer/` (the simulator cannot write the host
   `SAVE_GATE5_EVIDENCE_DIR`).
3. `scripts/capture-map-photo-pin-gate5.sh` reboots the simulator to
   dismiss a leftover SpringBoard location sheet, grants privacy,
   launches the DEBUG catalog and motion fixtures with
   `--uitest-location-denied`, takes screenshots, and records
   `xcrun simctl io recordVideo --codec=h264`.

## CI artifact

Workflow `CI` / job `ios-fast` uploads:

`save-map-photo-pins-gate5-<head-sha>`

Expected files:

- `imagerenderer/` — named SwiftUI snapshots (light, dark, `zh-Hant` 景點, P14)
- `xcattachments/` — the same PNGs as `XCTAttachment`s
- `simulator-catalog-light.png`
- `simulator-catalog-dark.png`
- `simulator-catalog-zh-Hant.png`
- `simulator-dark-coralCard.png`
- `simulator-map-light.png`
- `simulator-motion-end.png`
- `gate5-motion-60fps.mp4`

Named ImageRenderer stills now also include `zh-Hant-coralCardVisitedBack.png`
(去過 + locale date), `dark-coralCardBack.png`, `zh-Hant-foodCardHero.png`
(美食 · 吃), `light-shoppingBadge.png` (8-letter arc), and
`xxxLarge-photoBadge.png` (word path).

CI artifacts are the evidence location; a green run does not commit images into this folder.

Launch arguments (DEBUG only, not shipping):

- `--uitest-map-photo-pin-catalog`
- `--uitest-map-photo-pin-zh`
- `--uitest-map-photo-pin-motion`
- `--uitest-map-photo-pin-coral-card`
- `--uitest-map-photo-pin-card`
