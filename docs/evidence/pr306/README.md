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
| `*-home-thumbs.png` | Home DESIGN | Featured 44pt + recent 52pt; two-line Google / Maps under the thumb |
| `*-home-thumbs-en.png` | Home DESIGN | Same Home thumbs, English VoiceOver environment |
| `*-home-thumbs-zh-Hant.png` | Home DESIGN | Same Home thumbs, zh-Hant VoiceOver environment |
| `*-drawer-thumbs.png` | G2 v2 | Drawer search rows; mark in the card footer under the photo |
| `*-trip-stop.png` | G2 v2 | Trip stop paper card; mark in the footer, not overlaid |
| `*-origin-food.png` | G2 v2 | Origin food card; mark under the 326pt photo |
| `375-all-surfaces.png` | G2 v2 | 375pt width: Home, Drawer, Trip, Origin (Google + own) |
| `xxxl-all-surfaces.png` | G2 v2 | XXXL Dynamic Type, 16sp cap: same four surfaces |

CI artifact (DESIGN judges these PNGs, not the Linux checkout):

`pr306-google-photo-attribution-<sha>` from the `ios` workflow, written to `$RUNNER_TEMP/pr306-google-photo-attribution` by `SAVEGooglePhotoAttributionTests`.

Launch argument: `--uitest-google-photo-attribution`.

Home thumbs (DESIGN 2026-10-24): untranslated two-line `Google` / `Maps`, 10pt semibold, 2pt under the thumb, paper background, no bar. Light `#1F1F1F` on `#FFF9EB` and white on `#1E1C19` both ≥ 4.5:1. Google terms on wording/placement are still unverified; HoP / founder must confirm before treating overlay-on-photo as required.

Drawer / Trip / Origin still use the single-line footer mark. If that footer cannot fit, those surfaces show a non-Google image.

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

Expected verify query (founder `railway run`, not this agent):

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
      )
  ) as leftover_google_source_image_urls;
```

This Linux agent has no `DATABASE_URL` / Railway login, so it cannot attach
a live row count. Cleanup remains founder-owned and is not run here.
