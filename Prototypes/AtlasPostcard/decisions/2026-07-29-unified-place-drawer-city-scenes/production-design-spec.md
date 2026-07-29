# Unified Place Drawer + City Scenes

Status: implementation brief
Date: 2026-07-29

## Product gate

- Paid user job: turn a social-place clue into a trusted Map Stamp and Trip stop
  without losing context when a detail surface opens.
- Observed failure: Home, Saves, Root Map, Trip Map, review results, and public
  discovery can open visually different legacy drawers. The transition feels
  like leaving the approved Little Atlas + Postcard Pocket product.
- Classification: product-loop UI repair plus a small shareable delight layer.
- Demand proof: direct founder device feedback after build 100 identified the
  legacy drawer and requested more location-specific Home scenes.
- Pricing/paywall hypothesis: no new paywall in this slice. Consistent review
  and place details protect the core paid value; illustrated city scenes are a
  retention/share experiment.
- First distribution format: one comparison board containing the canonical
  drawer plus New York, Shanghai, and Seoul Home fixtures.

## Scope

### Canonical drawer

Every place selection must use one Postcard Drawer chrome:

- cream paper surface with a subtle top perforation;
- forest title and muted source/trust line;
- coral reserved for one primary action;
- share, Review, and close controls use the same outlined stamp buttons;
- saved place, review candidate, map candidate, and social place keep their
  existing actions and data contracts inside the shared chrome;
- collapsed, medium, and large detents preserve one identity;
- closing returns to the originating fixed Root or Trip tabs.

The persistent Map command shelf remains Map-only. Home and Saves open the
canonical task drawer as a sheet; they do not gain a permanent shelf.

### City scenes

Production scenes are illustration-only assets. City name, subtitle, Memo,
controls, pins, and live state remain SwiftUI layers.

- New York: Manhattan grid, Central Park, Hudson/East River, Statue of Liberty,
  Empire State Building, Brooklyn Bridge.
- Shanghai: Huangpu River, Bund, Oriental Pearl Tower, Shanghai Tower, historic
  shikumen roofs.
- Seoul: Han River, N Seoul Tower, Gyeongbokgung roofline, bridges and low hills.
- Tokyo and Taipei remain supported.
- Los Angeles, Beijing, Busan, and all other locations use the regional live-map
  base until a dedicated owned illustration ships.

Location matching uses the reverse-geocoded city name plus coarse coordinates.
It does not persist a new precise-location field or send location to a new
service.

## Design-taste brief

- Direction: illustrated travel keepsake with one tactile postcard drawer
- Density: comfortable in medium/large; compact but legible when collapsed
- Surface: continuous Little Atlas behind one cream paper drawer
- Type mood: friendly, editorial, compact
- Motion: gentle spring in, quick fade/slide out
- Do: keep one action hierarchy, use paper construction, preserve live data,
  keep map geography visible, use owned illustrations
- Don't: reuse neutral glass, nest generic notebook cards, show two drawers,
  bake text/Memo/UI into city art, or use more than one bright action color

Anti-slop check: one primary coral action, no generic pastel card dashboard,
no repeated glass cards, no whole-screen raster, and no city-specific layout
fork.

## Acceptance criteria

1. Home recent place, Saves Map Stamp, Saves Review Candidate, Root Map pin,
   Trip Map stop, and discovery result all route to one `place.detail.root`.
2. The drawer exposes `place.detail.postcardChrome` in collapsed and expanded
   states and no longer uses neutral `DrawerGlassBackground`.
3. Close returns to the originating fixed tab shell.
4. Deterministic Home fixtures resolve New York, Shanghai, and Seoul to owned
   city scenes; Tokyo and Taipei continue to resolve.
5. Unknown cities render the regional live-map fallback.
6. Generic unsigned simulator build exits 0.
7. Focused UI screenshots capture the drawer and three new city scenes on one
   402 x 874 simulator, then the simulator is shut down.

## Failure fixtures

- A Review Candidate opened from Saves renders a legacy notebook/glass header.
- A Root Map place detail dismisses to a sheet without reachable Root tabs.
- New York, Shanghai, or Seoul resolves to the generic map despite matching
  city name or coarse coordinates.
- Los Angeles, Beijing, or Busan incorrectly borrows another city's landmark
  art.
- A generated city asset contains baked text, pins, Memo, logo, UI, or a
  watermark.

## Systems and verification

- In scope: Atlas presentation, Home scene renderer, canonical detail drawer,
  owned city assets, deterministic UI fixtures/tests, design prompt/spec.
- Out of scope: parsers, auth, persistence schema, backend, MapKit navigation,
  new location permission, paywall, App Store/TestFlight release.
- Security/privacy: visual-only assets and local scene classification; existing
  Core Location and reverse geocoder remain the only location sources.
- Build:
  `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E
  -configuration Debug -destination 'generic/platform=iOS Simulator'
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex"
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build`
- UI proof: focused `SAVEScreenshotRailTests` methods on `SAV-E Codex UI`.
- Human approval still required: merge, TestFlight/App Store distribution, and
  any production release.
