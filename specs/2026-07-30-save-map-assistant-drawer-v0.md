# SAV-E Map Assistant Drawer v0

## Observed failure / paid user job

A user on the root Map must be able to open “Search places or ask SAV-E”
without being dropped into the legacy global Saved / Review / Friends command
drawer. The map command shelf should expand into one map-specific Postcard
Pocket assistant and keep the user anchored to Map.

## Classification

UI navigation bug fix. No backend, schema, parser, authentication, payment, or
location behavior changes.

## Acceptance criteria and failure fixture

1. From Root Map, tapping `Search places or ask SAV-E` presents one drawer.
2. The drawer has Postcard Pocket map-assistant content and the existing search
   field.
3. The legacy Saved / Review / Friends drawer tabs are absent in this context.
4. Existing Home, Saves, and Trips drawer entry points keep their behavior.
5. Root Map and its fixed root tab remain the underlying navigation context.
6. A focused UI regression test covers the presentation ownership.
7. The generic iOS Simulator build exits 0 without booting a simulator.

Failure fixture: launch the deterministic review-demo account, open Root Map,
tap `map.command.search`, then inspect the presented drawer.

## Demand, pricing, and distribution

- Demand proof: direct founder QA on TestFlight build 92.
- Pricing/paywall: unchanged; this repairs the core place-search interaction.
- First distribution format: atomic GitHub PR. TestFlight remains a separate,
  human-approved release action.

## Scope

- Root Map drawer launch routing.
- Map-specific idle drawer content.
- Focused UI regression test.

## Security and privacy

N/A: presentation-only change. Existing private Map Stamp boundaries, explicit
confirmation rules, and search services remain unchanged.

## Xcode context receipt

- Product/repo: SAV-E `/Users/jhinresh/projects/wanderly-current`
- Platform: iOS
- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Verification tier: build-only plus focused UI test authored for CI
- Generic destination: `generic/platform=iOS Simulator`
- Simulator reason: N/A for local verification
- Simulator lifecycle: not started
- Deployment target: iOS 17.0
- Existing build: `scripts/xcodebuild-clean.sh`
- Existing test: `SAVEUITests/SAVEScreenshotRailTests`
- DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP: N/A for build-only
- Attached physical device: ignored
- Free-space pressure: normal at 23 GiB
- Touched surface: SwiftUI Map drawer routing and presentation
- Skill route: `swift-xcode-workflow` + `swiftui-ui-patterns`
- Verification: generic simulator build
- Skipped verification: focused UI test is added but local runtime execution is
  skipped because this slice does not need to boot a simulator; CI is the UI
  checker

## Human approval still required

Merge, signing, TestFlight upload, App Store Connect changes, and release.
