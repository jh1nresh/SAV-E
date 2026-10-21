# Map photo-pin evidence (DESIGN gate 5)

Authoritative stills and the 60fps motion recording are produced on the
macOS CI runner from this SwiftUI code — not from composed HTML.

## How they are made

1. `SavvyMapPhotoPinSnapshotExport` (`#if DEBUG`) uses `ImageRenderer` on
   `SavvyMapPhotoPinPreviewCatalog` / cells / the P14 board.
2. `SAVETests.testGate5ImageRendererExportWritesLightDarkAndChinese` writes
   those PNGs and attaches them as `XCTAttachment`s.
3. `scripts/capture-map-photo-pin-gate5.sh` launches the DEBUG catalog and
   motion fixtures on the CI simulator, takes screenshots, and records
   `xcrun simctl io recordVideo --codec=h264`.

## CI artifact

Workflow `CI` / job `ios-fast` uploads:

`save-map-photo-pins-gate5-<sha>`

Expected files:

- `xcattachments/` — ImageRenderer PNGs (light, dark, `zh-Hant` 景點, P14)
- `simulator-catalog-light.png`
- `simulator-catalog-dark.png`
- `simulator-catalog-zh-Hant.png`
- `simulator-motion-end.png`
- `gate5-motion-60fps.mp4`

Launch arguments (DEBUG only, not shipping):

- `--uitest-map-photo-pin-catalog`
- `--uitest-map-photo-pin-zh`
- `--uitest-map-photo-pin-motion`
