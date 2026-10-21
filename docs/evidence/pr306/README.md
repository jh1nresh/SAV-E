# PR 306 Google photo attribution evidence

Real iOS Simulator captures from `SAVEGooglePhotoAttributionTests`.
The Linux agent cannot boot a simulator; CI writes these PNGs on the
macOS runner and uploads them as the `pr306-google-photo-attribution-<sha>`
workflow artifact. After that job, the PNGs are committed here so the
PR can show them without a Cursor login.

Light and dark sets:

| File | Scene |
| --- | --- |
| `*-google-carousel.png` | Google photo page in the card carousel |
| `*-user-photo.png` | User's own photo page (no Google chrome) |
| `*-full-screen.png` | Full-screen viewer |
| `*-author-page.png` | Page opened by tapping the author |
| `*-maps-page.png` | Page opened by tapping View on Google Maps |
| `*-logo-closeup.png` | Logo height and 10/10/10/5 clear space |
| `*-no-author.png` | Google photo with no author data → coral |

Launch argument: `--uitest-google-photo-attribution`.
