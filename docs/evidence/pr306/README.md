# PR 306 Google photo attribution evidence

Real iOS Simulator captures from `SAVEGooglePhotoAttributionTests`.
The Linux agent cannot boot a simulator; CI writes these PNGs on the
macOS runner and uploads them as the `pr306-google-photo-attribution-<sha>`
workflow artifact. After that job, the PNGs are committed here so the
PR can show them without a Cursor login.

Light and dark sets:

| File | Gate | Scene |
| --- | --- | --- |
| `*-google-carousel.png` | G2 | Google photo page: 44pt author + Google Maps logo |
| `*-user-photo.png` | G3 | User's own photo page (no Google chrome) |
| `*-mixed-card.png` | G3 | Google page with attribution beside an own photo |
| `*-full-screen.png` | G4 | Viewer with every author and View on Google Maps |
| `*-author-page.png` | G1 | Page opened by tapping an author (`/maps/contrib/`) |
| `*-maps-page.png` | G4 | Page opened by tapping View on Google Maps |
| `*-logo-closeup.png` | G2 | Logo height and 10/10/10/5 clear space |
| `*-no-author.png` | G1 | Google photo with no author data → coral |
| `*-map-pins.png` | G6 | Apple Map symbol pins, no Google photos |
| `*-city-page.png` | G7 | City card uses coral art, no Google photo |
| `*-report-entry.png` | G8 | Viewer “View on Google Maps” report entry |
| `*-home-thumbs.png` | Home DESIGN | Doodle Eat/Go stickers. No Google photo, no mark. |
| `*-home-thumbs-en.png` | Home DESIGN | Same Home sticker rows, English VoiceOver environment |
| `*-home-thumbs-zh-Hant.png` | Home DESIGN | Same Home sticker rows, zh-Hant VoiceOver environment |
| `*-drawer-thumbs.png` | G2 | Drawer search rows; single-line Google Maps footer under the row |
| `*-trip-stop.png` | G2 | Trip stop paper card; single-line Google Maps footer under the row |
| `*-origin-food.png` | G2 | Origin food card; single-line Google Maps footer under the photo |
| `*-atlas-thumbs.png` | G6 | Atlas `map.place.card` on Apple MapView: own/friend photo or coral. No Google photo, no mark. |
| `375-all-surfaces.png` | G2 | 375pt width: Home, Drawer, Trip, Origin, Atlas (Google + own) |
| `xxxl-all-surfaces.png` | G2 | XXXL Dynamic Type: same five surfaces |
| `xsmall-all-surfaces.png` | G2 | Minimum Dynamic Type (xSmall): same five surfaces |

CI artifact (DESIGN judges these PNGs, not the Linux checkout):

`pr306-google-photo-attribution-<sha>` from the `ios` workflow, written to `$RUNNER_TEMP/pr306-google-photo-attribution` by `SAVEGooglePhotoAttributionTests`.

Launch argument: `--uitest-google-photo-attribution`.

Home / Drawer / Trip / Origin / saved-postcard (DESIGN rejudge 2026-10-24): untranslated single-line `Google Maps`, 12–16sp regular (weight 400), 6pt from the photo, paper/canvas background, no bar, no wrap. Light `#1F1F1F` on `#FFF9EB` and white on `#1E1C19` both ≥ 4.5:1. Measure the full single-line width against the container, not the thumb; if it cannot fit, show a non-Google image. Stacked 10pt has no written basis.

Live Home after doodle v1 is Eat/Go stickers (`SaveDoodleSticker`). It has no Google photo and no mark. `SaveKraftStamp` leftover file still has a footer gate but product Home/Map/Passport must not call `SaveKraftStamp(`.

`map.place.card` is a callout over a live Apple MapView (G6): own/friend photo or coral, never a Google photo and never a mark. `SaveAtlasMapPlaceThumbnail` (56pt) uses `mapSafePhotoURL`. Detail (off the map) still shows Google photos with G1/G2/G4/G8 attribution. Google terms on wording/placement are still unverified; do not overlay the photo.

## SavedPostcardPhoto (G2) — actual image sources

`SavedPostcardPhoto` (`AIDrawerView`, 104pt) reads `detailPlace.businessPhotoURLStrings` only:

| Source | What it is | Mark? |
| --- | --- | --- |
| In-memory `Place.businessPhotoUrls` from `PlaceBusinessEnricher` | Live Places session URLs. Persist no longer writes this column. Usually Google. | Yes, if Google and 104pt fits the live 12–16sp line |
| In-memory leftover `businessPhotoUrls` | Same array, still held in the session Place after enrich / merge | Same gate |
| `Place.sourceImageUrl` appended by `businessPhotoURLStrings` | Social / import / user photo. Persist strips Google leftovers; G9 leftovers can still appear until founder cleanup | Yes only when the URL is still a Google Places photo |
| Empty / Google that cannot fit | Mint rectangle fallback | No |

`isDisplayable` already drops Google URLs when Maps is disallowed. Own / friend / social URLs stay unmarked. The 12–16sp clamp at `.xxxLarge` is still expected to fit 104pt; if a future live `markWidth` exceeds 104, the view shows the non-Google fallback instead of wrapping or shrinking the mark.

Contrast (P1-4): white author type over the cream fixture at gradient
top 0.55 measures **5.62:1** in `testAttributionWhiteTextMeetsContrastOnLightPhoto`.
Destination title/body use `#3A2415` on white so Dark Mode does not flip
them to cream. After CI writes these PNGs, sample the author-row pixels on
`*-google-carousel.png` and record the live ratio here.

## G5 — persist-only `place_id`, no photo-URL read

App / write path (this PR):

| Location | What it does |
| --- | --- |
| `SAV-E/Services/GooglePlacesService.swift` `PlaceBusinessPhotoPersistence.importedRemoteURLs` | Always returns `nil`. Hydration never reads stored photo URLs. |
| `SAV-E/Services/GooglePlacesService.swift` `GooglePlacesPhotoURL.persistableString` | Drops Places photo URLs and `photo_reference` values. `place_id` is the exempt durable field. |
| `SAV-E/Services/SupabaseService.swift` (~307, ~2017, `business_photo_urls` omit) | Writes omit `business_photo_urls` so a #306 install cannot clear rows. |
| `SAV-E/Services/SaveLocalVaultService.swift` | Local vault uses the same imported-nil + persistable-string path. |
| `backend/src/googlePlacesPhotoWrite.ts` | Server silently drops `business_photo_urls` and stores Google `source_image_url` as null. Non-Google import images pass through. Photo-only PATCH is a 200 no-op. |
| `backend/sql/google-photo-url-cleanup.sql` | Founder-only apply. Not run from this PR. |
| `backend/sql/google-photo-url-verify.sql` | Read-only leftover count. |

Expected verify query (founder `railway run`, not this agent).
Copy matches `backend/sql/google-photo-url-verify.sql` line for line so QA can tick each Googleusercontent Places path:

```sql
select
  (
    select count(*)
    from public.places
    where coalesce(cardinality(business_photo_urls), 0) > 0
  ) as leftover_business_photo_urls,
  (
    select count(*)
    from public.places
    where source_image_url is not null
      and (
        source_image_url ilike '%maps.googleapis.com/maps/api/place/photo%'
        or source_image_url ilike '%places.googleapis.com%/%/media%'
        or source_image_url ilike '%photo_reference=%'
        or source_image_url ~* '^places/.+/photos/'
        or source_image_url ilike '%googleusercontent.com%/places/%'
        or source_image_url ilike '%googleusercontent.com%/place-photos/%'
        or source_image_url ilike '%googleusercontent.com%/p/%'
        or source_image_url ilike '%googleusercontent.com%/gps-cs-s/%'
        or source_image_url ilike '%googleusercontent.com%/gps-proxy/%'
      )
  ) as leftover_google_source_image_urls;
```

QA tick list for leftover `source_image_url` (same five googleusercontent Places styles as cleanup):

1. `source_image_url ilike '%googleusercontent.com%/places/%'`
2. `source_image_url ilike '%googleusercontent.com%/place-photos/%'`
3. `source_image_url ilike '%googleusercontent.com%/p/%'`
4. `source_image_url ilike '%googleusercontent.com%/gps-cs-s/%'`
5. `source_image_url ilike '%googleusercontent.com%/gps-proxy/%'`

Do not treat avatar paths `/a/` or `/a-/` as leftovers. Cleanup uses the same five `ilike` rows in `backend/sql/google-photo-url-cleanup.sql`.

This Linux agent has no `DATABASE_URL` / Railway login, so it cannot attach
a live row count. Cleanup remains founder-owned and is not run here.
