# SAV-E Light Postcard Appearance v0

## Observed failure / paid user job

SAV-E users currently encounter a mixture of dark system material and light
Postcard Pocket artwork when their phone uses Dark Mode. The approved
illustrations, paper textures, and postcard hierarchy are light-first, so the
product appears to switch visual systems between screens.

## Classification

UI consistency maintenance. This does not add a new theme or change product
behavior.

## Acceptance criteria and failure fixture

1. The shipping SAV-E app declares `UIUserInterfaceStyle = Light` once at the
   app boundary.
2. Home, Saves, Trips, Map, Passport, Drawer, alerts, sheets, and UIKit-hosted
   controls inherit the same Light appearance.
3. The App Clip also declares Light appearance.
4. Share Extension and iMessage remain Light as already configured.
5. No screen-level `.preferredColorScheme` modifiers are introduced.
6. Built main-app and App Clip Info.plists both contain
   `UIUserInterfaceStyle = Light`.
7. The generic iOS Simulator build exits 0 without booting a simulator.

Failure fixture: build while the host Mac or test iPhone is using Dark Mode,
then inspect the generated Info.plists and launch any production surface.

## Demand, pricing, and distribution

- Demand proof: direct founder QA on TestFlight build 92.
- Pricing/paywall: unchanged; this repairs the approved product identity.
- First distribution format: atomic GitHub PR. TestFlight remains a separate,
  human-approved release action.

## Scope

- Main app Info.plist appearance metadata.
- App Clip generated Info.plist setting.
- XcodeGen source of truth and generated Xcode project.

No view-by-view restyling, dark-theme asset work, backend, parser, auth,
payment, schema, or deployment changes.

## Security and privacy

N/A: appearance metadata only. No data collection, permission, network, secret,
or account boundary changes.

## Xcode context receipt

- Product/repo: SAV-E `/Users/jhinresh/projects/sav-e`
- Platform: iOS
- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE` with embedded `SAVEClip`
- Verification tier: build-only
- Generic destination: `generic/platform=iOS Simulator`
- Simulator reason: N/A
- Simulator lifecycle: not started
- Deployment target: iOS 17.0
- Existing build: `scripts/xcodebuild-clean.sh`
- Existing test: Info.plist read-back plus generic build
- DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP: N/A for build-only
- XcodeBuildMCP owner count: 0
- Attached physical device: ignored
- Free-space pressure: normal at 22 GiB
- Touched surface: app and App Clip appearance metadata
- Skill route: `swift-xcode-workflow` + `swiftui-ui-patterns`
- Verification: XcodeGen diff, plist read-back, generic simulator build
- Skipped verification: runtime screenshot comparison; app-level plist
  metadata is deterministic and does not require a booted simulator

## Human approval still required

Merge, signing, TestFlight upload, App Store Connect changes, and release.
