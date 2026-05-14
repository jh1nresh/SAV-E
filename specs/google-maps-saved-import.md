# Google Maps Saved Places Import

## Goal

Let a user bring their existing Google Maps saved places into Wanderly so the app starts with real personal places instead of one-by-one sharing.

## Product Decision

The first product-ready version should import from Google Takeout, not promise a one-tap Google Maps OAuth sync.

Google Maps exposes saved lists in the Maps product and supports exporting saved lists through Google Takeout. Google Maps Platform Places APIs can refine place data, but they are not a consumer API for reading a user's private Google Maps saved lists directly.

## User Flow

1. User opens Wanderly import.
2. Wanderly shows a short instruction: export Google Maps saved places from Google Takeout with `Saved` selected.
3. User selects the downloaded Takeout `.zip` or extracted file.
4. Wanderly previews parsed lists and places.
5. User chooses lists to import.
6. Wanderly deduplicates against existing `sourceUrl`, Google Place ID, coordinates, name, and address.
7. Wanderly saves selected places to the user's account.

## Data Sources

### Primary

- Google Takeout export with Maps saved lists.
- Expected file formats may include JSON/GeoJSON/KML-like data depending on Google export shape, so parser should detect supported files rather than hardcode one path only.

### Enrichment

- Google Places Text Search / Place Details when a Takeout item has a name or address but no stable Google Place ID.
- Existing deterministic map URL coordinate parser for shared Google Maps URLs.

## Native iOS Scope

- Add an import entry point in Profile or My Places.
- Use `UIDocumentPickerViewController` for `.zip`, `.json`, `.geojson`, `.kml`.
- Parse locally first.
- Save through existing `SupabaseService.savePlace`.
- Show import progress and result counts:
  - imported
  - skipped duplicates
  - needs review
  - failed

## RN Web Scope

- Add an import panel in Places.
- Use file input for `.zip` or extracted files.
- Save through existing backend API.
- Guest users can import into their guest profile; signed-in users import into their authenticated profile.

## Import Semantics

- Imported Google Maps places should use `sourcePlatform = googleMaps`.
- Preserve original list name as a note or future collection tag.
- Do not create fake coordinates. If no coordinates or confident refinement exists, create a review draft rather than a map pin at `(0,0)`.
- Do not require AI for deterministic Google Maps imports.
- AI may only classify category or summarize notes after deterministic place identity is established.

## Deduplication

Use this order:

1. Google Place ID match, when available.
2. Normalized source URL match.
3. Coordinate distance within a small threshold plus normalized name match.
4. Normalized name plus normalized address match.

## Acceptance Criteria

- User can import a Google Takeout file and see parsed places before saving.
- Imported places appear in saved places immediately after import.
- Imported places persist after app restart.
- Duplicate import of the same Takeout file does not create duplicate saved places.
- Places without reliable coordinates are marked for review and do not create incorrect map pins.
- Existing Share Extension import behavior remains unchanged.

## Non-Goals

- No claim of automatic background sync from Google Maps.
- No scraping Google Maps web UI.
- No browser-cookie based import.
- No broad OAuth permission request until a supported Google API exists for this data.
