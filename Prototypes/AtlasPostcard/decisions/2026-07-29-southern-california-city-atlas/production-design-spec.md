# Southern California Home Atlas v0

Status: implementation slice
Date: 2026-07-29
Canonical visual source: `Prototypes/AtlasPostcard/design.md`

## Required brief

- **Paid user job / observed failure:** a SAV-E user in Los Angeles or Orange
  County should see a local illustrated keepsake on Home. Today Tustin and
  nearby cities fall back to the generic regional map even though Home already
  has owned scenes for Tokyo, Taipei, New York, Shanghai, and Seoul.
- **Acceptance criteria:** Los Angeles and Orange County names or coordinates
  resolve to one owned Southern California atlas asset; the city name remains
  live SwiftUI; unsupported American cities still use the regional live map.
- **Failure fixture:** Tustin at `33.7459, -117.8265` must render the Southern
  California asset. San Francisco at `37.7749, -122.4194` must not.
- **Classification:** narrow product presentation slice.
- **Demand proof:** the founder explicitly selected Southern California as the
  next city scene after reviewing the first three new production scenes.
- **Pricing/paywall hypothesis:** no new paywall. The scene improves first-open
  recognition and retention inside the existing product.
- **First distribution format:** PR screenshot plus a focused deterministic UI
  fixture. TestFlight remains a separate human-controlled release action.
- **Files and systems in scope:** Atlas Home presentation, Home asset catalog,
  city prompt/provenance manifests, deterministic UI fixture, and focused UI
  test.
- **Verification:** generic unsigned iOS Simulator build; focused Home UI test
  for Tustin; existing unsupported-city fixture remains regional-map backed;
  asset manifest JSON validation; diff and secret-pattern checks.
- **Security/privacy boundary:** use only the existing resolved region title and
  coarse coordinates already consumed by Home. Add no permission, persistence,
  analytics, network service, or precise-location history.
- **Human approval still required:** merge, signing, TestFlight, App Store
  Connect, and production distribution.

## Design-taste brief

- **Direction:** warm illustrated Southern California field atlas
- **Density:** spacious atlas hero; production content below remains unchanged
- **Surface:** one continuous watercolor geography, not a card collage
- **Type mood:** friendly, editorial, compact; city text remains live
- **Motion:** existing gentle Home transition; no new ornamental animation
- **Do:** show Pacific coast, Los Angeles skyline, Griffith Observatory,
  Santa Monica Pier, palm-lined Orange County neighborhoods, and low-rise
  coastal blocks; preserve a quiet center for the live city title and lower
  center for Memo
- **Don't:** bake text, labels, pins, logo, Memo, UI, the Hollywood sign,
  Disneyland or other protected characters/attractions into the bitmap; do not
  use the asset for San Diego, San Francisco, or all of California

## Xcode context receipt

- **Product/repo:** SAV-E, `/Users/jhinresh/projects/sav-e`
- **Platform:** iOS
- **Project:** `SAV-E.xcodeproj`
- **Scheme/target:** `SAV-E`
- **Verification tier:** build-only first, then focused UI
- **Generic destination:** `generic/platform=iOS Simulator`
- **Runtime simulator:** one temporary iPhone 17 Pro on the installed latest
  iOS runtime
- **Simulator reason:** prove the Tustin fixture selects the owned scene and
  capture the production Home composition
- **Simulator lifecycle:** not started; final runtime gate must shut down and
  delete the temporary device
- **Deployment target:** iOS 17
- **Existing build command:** repository `scripts/xcodebuild-clean.sh` generic
  simulator build from `AGENTS.md`
- **Existing test command:** XcodeBuildMCP `test_sim` with one
  `SAVEScreenshotRailTests` method
- **Canonical DerivedData:** `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- **XcodeBuildMCP status:** project, scheme, configuration, and DerivedData
  defaults set; simulator intentionally deferred until the UI gate
- **Touched surface:** SwiftUI presentation selection and owned raster asset
- **Selected skill route:** `swift-xcode-workflow` plus
  `build-ios-apps:swiftui-ui-patterns`
- **Verification command:** generic build followed by the focused UI test
- **Skipped verification reason:** N/A

## Scene boundary

The bitmap is a Los Angeles–Orange County regional keepsake. Name matching may
recognize common LA/OC cities, while the coordinate match stays bounded to the
LA basin and Orange County. The live resolved place title is authoritative;
the image contains no embedded city name.

San Diego, San Francisco, Las Vegas, and other American locations keep the
generic regional map until they receive their own reviewed asset.

## Anti-slop gate

- One continuous atlas scene, not nested pastel cards.
- Existing forest, cream, coral, mint, and powder-blue palette only.
- No extra action color, typography, badge, or decorative UI.
- No pure black, heavy shadow, photorealism, stock map screenshot, or generated
  text.
- The scene should still read as SAV-E when the live title and Memo are removed.
