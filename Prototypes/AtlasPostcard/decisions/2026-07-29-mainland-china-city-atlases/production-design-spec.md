# Mainland China Home Atlases v0

Status: implementation slice
Date: 2026-07-29
Canonical visual source: `Prototypes/AtlasPostcard/design.md`

## Required brief

- **Paid user job / observed failure:** a SAV-E user in a major mainland China
  city should see a local illustrated keepsake on Home rather than a generic
  regional map. Shanghai already has an owned scene; Beijing, Guangzhou,
  Shenzhen, and Chengdu do not.
- **Acceptance criteria:** reviewed city names or bounded city coordinates
  select one owned scene for Beijing, Guangzhou, Shenzhen, or Chengdu; the
  resolved city name remains live SwiftUI; nearby unsupported cities keep the
  regional live-map fallback.
- **Failure fixtures:** Beijing, Guangzhou, Shenzhen, and Chengdu coordinates
  must select their matching scenes. Tianjin, Foshan, Dongguan, and Chongqing
  must not borrow one.
- **Classification:** narrow product presentation slice.
- **Demand proof:** the founder explicitly requested more mainland China city
  scenes after selecting the existing regional-atlas direction.
- **Pricing/paywall hypothesis:** no new paywall. Local recognition improves
  first-open trust and retention inside the existing product.
- **First distribution format:** PR asset preview plus deterministic unit and
  UI fixtures. TestFlight remains a separate human-controlled release action.
- **Files and systems in scope:** Atlas Home scene selection, four Home asset
  catalog entries, generation prompts/provenance, deterministic fixtures, and
  focused tests.
- **Verification:** asset dimension and manifest validation; focused scene
  selection unit tests; generic unsigned iOS Simulator build; CI-owned runtime
  checks; diff and secret-pattern checks.
- **Security/privacy boundary:** use only the existing resolved locality title
  and coarse coordinates. Add no permission, persistence, analytics, network
  service, or precise-location history.
- **Human approval still required:** merge, signing, TestFlight, App Store
  Connect, and production distribution.

## Selected cities

| Scene | Recognizable forms | Nearby fallback fixture |
|---|---|---|
| Beijing | Temple of Heaven, Forbidden City roofs, hutong courts, CCTV Headquarters, lakes | Tianjin |
| Guangzhou | Canton Tower, Pearl River, Chen Clan roofs, Shamian arcades, banyan-lined blocks | Foshan |
| Shenzhen | Futian skyline, Ping An Finance Centre, Shenzhen Bay, Lianhuashan, mangroves | Dongguan |
| Chengdu | West Pearl Tower, Kuanzhai roofs, shrine garden, Jin River, bamboo and foothills | Chongqing |

The set deliberately adds geographic and visual range. Shanghai remains the
east-coast scene; another generic skyline-only city would add less recognition.

## Xcode context receipt

- **Product/repo:** SAV-E, `/Users/jhinresh/projects/wanderly-current`
- **Platform:** iOS
- **Project:** `SAV-E.xcodeproj`
- **Scheme/target:** `SAV-E`
- **Verification tier:** build-only locally; logic tests and UI checks in CI
- **Generic destination:** `generic/platform=iOS Simulator`
- **Simulator reason:** local runtime gate blocked because free disk was 9.6
  GiB, below the repository's 10 GiB minimum; CI owns the temporary simulator
- **Simulator lifecycle:** not started locally
- **Deployment target:** iOS 17
- **Existing build command:** repository `scripts/xcodebuild-clean.sh` generic
  simulator build from `AGENTS.md`
- **Existing test command:** `SAVETests` plus deterministic
  `SAVEScreenshotRailTests` fixtures
- **Canonical DerivedData:** `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- **XcodeBuildMCP status:** project, scheme, configuration, and DerivedData
  defaults confirmed; simulator intentionally unset
- **Touched surface:** SwiftUI presentation selection and owned raster assets
- **Selected skill route:** `swift-xcode-workflow` plus
  `build-ios-apps:swiftui-ui-patterns`
- **Verification command:** focused unit test and generic build; CI read-back
- **Skipped verification reason:** local UI runtime skipped only because the
  disk-space safety gate blocks it

## Scene boundary

Name matching accepts common English, Simplified Chinese, and Traditional
Chinese locality forms. Coordinate boxes stay around each urban core and do
not claim an entire province or megaregion. City text remains authoritative and
is never baked into the image.

Unsupported cities keep the live regional map until they receive a reviewed
asset. The app must never substitute the nearest illustrated city merely
because it is in mainland China.

## Anti-slop gate

- One continuous atlas scene, not nested pastel cards.
- Existing forest, cream, coral, mint, powder-blue, and muted-teal palette only.
- No baked text, city labels, pins, badges, logo, Memo, UI, watermark, flags,
  political symbols, brand marks, or protected characters.
- No stock map screenshot, photorealism, pure black, or heavy shadow.
- Preserve a quiet center for live city text and lower center for Memo.
- Each scene must still read as SAV-E when the live overlays are removed.
