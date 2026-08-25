# Savvy App Store Screenshots v3 Notes

## Source

Generated from `specs/app-store-screenshot-board.html` with:

```bash
node specs/export-app-store-screenshots.mjs
```

The exporter writes:

- `specs/app-store-screenshots/v3/` — iPhone portrait, 1242×2688
- `specs/app-store-screenshots/v3-ipad-13/` — 13-inch iPad portrait, 2048×2732

These are faithful mock equivalents, not raw simulator captures. The outer poster frame stays editorial; the iPhone interiors are rebuilt to look like simplified current Savvy app states.

## Screenshot Mapping

1. `01-stop-losing-friend-places.png`
   - Maps to the main map and bottom drawer save flow.
   - Shows a friend-sent place becoming a private map save.
   - Primary action: `Save to map`.

2. `02-paste-link-save-place.png`
   - Maps to source link recovery and review-candidate creation.
   - Shows pasted social URL input becoming one clean place candidate.
   - Primary action: `Review first`.

3. `03-confirm-before-counts.png`
   - Maps to the review candidate confirmation flow.
   - Shows human-readable evidence snippets instead of confidence meters.
   - Primary action: `Confirm place`.

4. `04-ask-your-private-map.png`
   - Maps to the Savvy routed assistant / saved-map query surface.
   - Shows a question answered from saved places and remembered sources.
   - Primary action: `Ask Savvy`.

5. `05-private-place-passport.png`
   - Maps to the Profile / Passport surface.
   - Shows private city memory, recent remembered places, and saved cities.
   - Primary action: `View passport`.

## Known Deviations

- Demo data is seeded and non-personal.
- The phone interiors are simplified for App Store readability; they are not exact pixel-for-pixel SwiftUI captures.
- The Instagram line is abstracted to `instagram.com/reel/...` and does not imply third-party endorsement.
- Passport content is a faithful representation of the current Profile/Passport concept, not a new achievement system.

## Removed Risky Signals

- Full fake social preview cards.
- Tiny tab/chip stacks that were unreadable in the contact sheet.
- Confidence dashboards or `AI Result` style claims.
- Multiple competing CTAs inside the same phone screen.
