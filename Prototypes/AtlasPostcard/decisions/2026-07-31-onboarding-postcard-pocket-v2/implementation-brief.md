# SAV-E Onboarding Postcard Pocket v2 — Implementation Brief

## Paid User Job / Observed Failure

New users must understand that SAV-E turns an uncertain place clue into a
user-confirmed private Map Stamp. The current Clue, Review, and Map Stamp pages
use the right palette but three unrelated constructions, so first run does not
teach the production Postcard Pocket system.

## Acceptance Criteria and Failure Fixture

- Clue, Review, and Map Stamp use the same fixed kraft pocket stage and the
  same scalloped object silhouette.
- State changes remain semantic: coral Source Clue, sky Review Candidate, mint
  confirmed Map Stamp.
- The source remains visibly retained through Review and Map Stamp.
- Clue remains editable and cannot advance while empty; the existing sample
  action remains reachable.
- Review still requires an explicit primary action before the Map Stamp proof.
- Language, navigation, skip behavior, completion callback, and accessibility
  identifiers remain unchanged.
- At 402 x 874 pt, each page shows its title, pocket stage, primary action, and
  skip action without scrolling or clipping.
- Failure fixture: the final PR #63 screenshots where Clue uses floating source
  chips, Review uses a checklist card, and Map Stamp uses a generic mini-map
  panel.

## Classification

First-run activation-loop UI correction. No new product capability.

## Demand, Pricing, and Distribution

- Demand proof: founder rejected the current three screenshots and explicitly
  approved the One Postcard, Three States direction.
- Pricing/paywall: N/A — this is first-run comprehension for the existing app.
- First distribution format: existing TestFlight onboarding flow and PR UI
  screenshot artifact.

## Scope

- `SAV-E/Views/Onboarding/OnboardingView.swift`
- Existing Atlas/Postcard theme components and owned assets only.
- First-run UI tests may receive structural assertions; data contracts do not
  change.

## Verification Commands

1. Static checks and generic iOS Simulator build using the canonical DerivedData
   root.
2. Focused `SAVEOnboardingCarouselTests` runtime gate for the three screenshots.
3. Inspect the three exported screenshots at the 402 x 874 pt review viewport.

## Security and Privacy Boundary

Security scan: N/A — local SwiftUI presentation only. No network, auth,
persistence, parser, entitlement, or secret path changes. The confirmation gate
and private/source-retained claims must remain unchanged.

## Human Approval Still Required

Merge, TestFlight upload, App Store submission, or any cache/process deletion.

## Xcode Context Receipt

- Product/repo: SAV-E `/Users/jhinresh/projects/sav-e`
- Platform: iOS
- Project/workspace/package: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Verification tier: build-only first, then UI screenshot gate
- Generic destination or simulator/device and OS: `generic/platform=iOS Simulator`; focused headless iPhone 16 Pro on iOS 26.5
- Simulator reason: capture and verify Clue, Review, and Map Stamp runtime UI
- Simulator lifecycle: headless booted `87A7716F-29F9-4CB7-847A-966823C92362`; Shutdown and deletion verified
- Deployment target: iOS 17.0
- Existing build command: `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build`
- Existing test command: focused `SAVEOnboardingCarouselTests` via `xcodebuild test`
- Canonical DerivedData root: `$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP status: available but not used for build-only
- XcodeBuildMCP owner count: 0; direct `xcodebuild` used
- Attached physical device: ignored
- Free-space pressure: cleanup approved and completed; runtime began at 25.1 GiB and finished with 21.8 GiB free
- Touched surface: SwiftUI first-run composition only
- Selected skill route: `swift-xcode-workflow` + `build-ios-apps:swiftui-ui-patterns`
- Verification command: generic build above, then `xcodebuild test -only-testing:SAVEUITests/SAVEOnboardingCarouselTests/testProofFirstFlowReachesOpenAppCTA`
- Skipped verification reason: N/A
