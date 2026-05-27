# Import Paths Separation

## Goal

Keep SAV-E's two Google import paths separate so saved-list link work does not break historical Google Takeout bulk import.

## Import Surfaces

### Google Maps Saved List Import

- Trigger: iOS Share Sheet or clipboard URL import with a public Google Maps saved-list link.
- Primary code: `WanderlyShareExtension/ShareViewController.swift` and `WanderlyShared/GoogleMapsListPlaceExtractor.swift`.
- Output: multiple review candidates.
- Rule: never save places directly from a saved-list link without review.

### Google Takeout Bulk Import

- Trigger: native file picker for `.zip`, `.json`, `.geojson`, or `.kml` Google Takeout exports.
- Primary code: `Wanderly/Views/Import/GoogleTakeoutImportView.swift`, `Wanderly/Services/GoogleTakeoutImportService.swift`, and `Wanderly/Models/GoogleTakeoutImport.swift`.
- Output: ready-to-save imported drafts plus review drafts.
- Rule: only drafts with reliable coordinates become saved map places.

## Decision

No shared importer base class, no single ambiguous import screen, and no silent routing between saved-list link parsing and Takeout file parsing.

## Acceptance Criteria

- Drawer labels historical bulk import as Takeout, not generic Import.
- Saved-list share extraction has a focused test that produces multiple candidates.
- Takeout parsing has focused tests for supported flat files and ZIP-contained exports.
- Comments near each importer identify the boundary.
