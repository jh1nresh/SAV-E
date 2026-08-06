# SAV-E Atlas Saves, Drawer, and Map Recovery v0

## Observed failure / paid user job

A SAV-E user must be able to review every captured clue, browse every confirmed
Map Stamp, open one complete place detail, and return to the originating Saves
or Map surface. Founder QA found that production currently exposes only three
Review items, Review appears inert, My Stamps falls back to the retired visual
renderer and traps navigation, and Map details omit useful place information.

## Classification

Bug fix and UI convergence maintenance. This is not a new feature or a backend
schema change.

## Acceptance criteria and failure fixtures

1. A seeded Review queue with more than three candidates can be browsed in
   Saves without leaving the Atlas visual shell.
2. Review and My Stamps visibly switch within one Saves renderer.
3. Tapping any Review candidate opens its canonical detail in the one global
   drawer.
4. Tapping any Map Stamp opens the same Atlas-styled place detail and closing
   it restores Saves with its selected segment and root tabs.
5. Tapping a Root Map marker shows name, area/address, confirmed state, note or
   source context, and its primary detail action.
6. Closing Root Map detail restores Map and the fixed root tabs.
7. Focused production-path UI tests and the generic simulator build exit 0.
8. One task-owned headless simulator is shut down after evidence.

## Demand, pricing, and distribution

- Demand proof: direct founder QA against the production UI.
- Pricing/paywall: unchanged; this repairs the core saved-place job.
- First distribution format: reviewed PR screenshots, then a human-approved
  TestFlight build in a separate release action.

## Scope

- `SaveLibraryView` and Atlas Saves presentation/components.
- The canonical map/place detail drawer and its navigation ownership.
- Root Map selected-place presentation.
- Focused UI regression tests and CI selection.

No backend, parser, authentication, payment, schema, or release changes.

## Security and privacy

N/A for security scanning: the patch changes local presentation and navigation
only. Existing private place data boundaries and explicit confirmation rules
remain unchanged.

## Xcode context receipt

- Product/repo: SAV-E `/Users/jhinresh/projects/sav-e`
- Platform: iOS
- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Verification tier: UI
- Generic destination: `generic/platform=iOS Simulator`
- Runtime: one task-owned headless iOS 26.5 simulator
- Simulator reason: reproduce Saves segment/detail navigation and Map detail
- Simulator lifecycle: completed; `SAV-E UI Gate` verified `Shutdown`
- Deployment target: iOS 17.0
- Existing build: `scripts/xcodebuild-clean.sh ... CODE_SIGNING_ALLOWED=NO build`
- Existing test: focused `SAVEUITests/SAVEScreenshotRailTests`
- DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP: project, scheme, configuration, DerivedData, and bundle defaults set
- Touched surface: SwiftUI Saves, drawer, Map selection, UI tests
- Skill route: `swift-xcode-workflow` + `swiftui-ui-patterns`
- Verification: generic build and two focused production UI tests
- Skipped verification: the full test suite was not run; the two affected
  production flows were exercised end to end

## Human approval still required

Merge, deployment, signing, TestFlight upload, App Store Connect changes, and
production release.
