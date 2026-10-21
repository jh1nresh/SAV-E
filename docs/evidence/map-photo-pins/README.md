# Map photo-pin evidence (DESIGN gate 5)

Authoritative stills and the 60fps motion recording are produced on the
macOS CI runner from this SwiftUI code — not from composed HTML.

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
- `simulator-motion-end.png`
- `gate5-motion-60fps.mp4`

Committed copies of the named stills also live in this folder after a
green `ios-fast` run.

Launch arguments (DEBUG only, not shipping):

- `--uitest-map-photo-pin-catalog`
- `--uitest-map-photo-pin-zh`
- `--uitest-map-photo-pin-motion`
