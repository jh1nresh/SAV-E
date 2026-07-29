# SAV-E Home Regional Atlas Hero v0

## Paid user job / observed failure

When a traveler opens SAV-E, Home should feel connected to where they are now
instead of always looking like a Tokyo demo. The approved Atlas/Postcard visual
language must remain intact.

## Classification

Core Home UI correction with a small location-aware enhancement. No backend,
schema, parser, account, payment, or trip-planning change.

## Acceptance criteria and failure fixtures

1. Production Home does not always render the static Tokyo hero.
2. With foreground location permission, the resolved locality selects a
   founder-approved illustrated city scene. Taipei renders recognizable Taipei
   101, Chiang Kai-shek Memorial Hall, Longshan Temple, waterways, and nearby
   mountain forms in the same visual family as the approved Tokyo scene.
3. The hero includes restrained mascot motion that does not move primary
   controls and respects Reduce Motion.
4. If location is unavailable, Home uses the newest confirmed Map Stamp as its
   regional fallback.
5. If SAV-E does not yet have a city scene for the resolved locality, Home
   renders the regional-map fallback with no fabricated landmark.
6. The parity fixture and a resolved Tokyo locality keep the approved Tokyo
   illustration, including Tokyo Tower and the existing landmark composition.
7. Existing Home actions and the fixed root tab remain reachable.
8. Generic iOS Simulator build exits 0; one focused headless UI check verifies
   the production regional hero and its fallback.

## Demand, pricing, and distribution

- Demand proof: direct founder feedback that the Home hero feels fixed to Tokyo.
- Pricing/paywall: unchanged; this improves the core first-open experience.
- Distribution: update the existing Atlas PR. Any TestFlight distribution
  remains a separate human-approved action.

## Scope

- `SaveHomeView`
- Atlas Home city-scene selection and hero renderer
- founder-owned Taipei city-atlas raster asset at 1x, 2x, and 3x
- existing `LocationService` consumption
- focused Home UI coverage

No new dependency, external asset license, backend endpoint, or persistent
location field. The Taipei illustration is generated specifically for SAV-E
from the founder-approved local Tokyo scene as a style/composition reference.

## Security and privacy

- Request location only while Home is active and only through the existing
  when-in-use permission.
- Keep the exact coordinate in memory only.
- Present locality/administrative-area/country labels, never street address.
- Do not transmit the current coordinate to SAV-E services or persist it.
  Reverse geocoding stays inside Apple's system location/geocoding services.

## Xcode context receipt

- Product/repo: SAV-E `/Users/jhinresh/projects/wanderly-current`
- Platform: iOS
- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Verification tier: UI
- Generic destination: `generic/platform=iOS Simulator`
- Runtime: one task-owned headless iOS 26.5 simulator
- Simulator reason: verify production Home regional fallback and motion-safe
  visual state
- Simulator lifecycle: `SAV-E UI Gate` headless runtime shut down and deleted;
  absence verified
- Deployment target: iOS 17.0
- Existing build: `scripts/xcodebuild-clean.sh ... CODE_SIGNING_ALLOWED=NO build`
- Existing test: focused `SAVEUITests/SAVEScreenshotRailTests`
- DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP: verify defaults before build/test
- Touched surface: SwiftUI Home hero, city-scene asset selection, in-memory
  location presentation, UI test
- Skill route: `swift-xcode-workflow` + `swiftui-ui-patterns` + `imagegen`
- Verification: generic build, focused production regional-hero UI test, and
  Atlas parity fixture UI test
- Skipped verification: full suite; CI is the canonical full checker

## Human approval still required

Merge, signing, TestFlight upload, App Store Connect changes, deployment, and
production release.
