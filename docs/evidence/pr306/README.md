# PR 306 Google photo attribution evidence

Real iOS Simulator captures from `SAVEGooglePhotoAttributionTests`.
The Linux agent cannot boot a simulator; CI writes these PNGs on the
macOS runner and uploads them as the `pr306-google-photo-attribution-<sha>`
workflow artifact. After that job, the PNGs are committed here so the
PR can show them without a Cursor login.

Light and dark sets:

| File | Scene |
| --- | --- |
| `*-google-carousel.png` | Google photo page: 44pt author+logo row (Maps is full-screen only) |
| `*-user-photo.png` | User's own photo page (no Google chrome) |
| `*-full-screen.png` | Full-screen viewer with every author and View on Google Maps |
| `*-author-page.png` | Page opened by tapping an author on the viewer |
| `*-maps-page.png` | Page opened by tapping View on Google Maps |
| `*-logo-closeup.png` | Logo height and 10/10/10/5 clear space |
| `*-no-author.png` | Google photo with no author data → full coral + cream icon |

Launch argument: `--uitest-google-photo-attribution`.

Contrast (P1-4): white author type over the cream fixture at gradient
top 0.55 measures **5.62:1** in `testAttributionWhiteTextMeetsContrastOnLightPhoto`.
After CI writes these PNGs, sample the author-row pixels on
`*-google-carousel.png` and record the live ratio here.
