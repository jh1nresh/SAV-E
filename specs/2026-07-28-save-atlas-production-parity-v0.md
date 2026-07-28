# SAV-E Atlas/Postcard Production Parity v0

## Product brief

- **Paid user job / observed failure:** A SAV-E user needs to turn saved social
  links into confirmed place memory and a usable trip without the product
  feeling like four unrelated generic dashboards. The observed failure is that
  the production Home, Saves, Plan, and Map screens score below the approved
  visual reference and do not preserve its atlas/pocket composition.
- **Classification:** Product UI refactor with deterministic visual regression.
- **Demand proof:** The founder explicitly rejected the current production
  visual rebuild and approved the Little Atlas + Postcard Pocket reference.
- **Pricing / paywall hypothesis:** N/A for this visual correction; no commerce
  behavior changes.
- **First distribution format:** Existing iOS TestFlight flow after a separate
  human-approved merge and deploy. This PR does not deploy.

## Canonical contract

[`../Prototypes/AtlasPostcard/design.md`](../Prototypes/AtlasPostcard/design.md)
is the visual source of truth for the four scoped pages. Existing auth,
persistence, link confirmation, trip editing/export, and the one canonical
place-detail drawer remain unchanged.

## Scope

- Port the verified prototype component tree into the production app target.
- Bind Home, Saves, Plan, and Map text/counts/actions to production data.
- Promote the approved section-level assets into the production asset catalog
  at 1x/2x/3x.
- Add a deterministic production fixture and screenshot/parity gate.
- Keep one fixed Root tab shell and one fixed Trip tab shell.

## Do not touch

- Backend, database schema, auth, link parsing, confirmation rules, sharing
  contracts, KML content, deployment, App Store Connect, or TestFlight.
- Whole-screen screenshot backgrounds.
- Existing SAV-E logo/Memo artwork.

## Acceptance criteria

1. Home, Saves, Trip Plan, and Root Map render within one 402 x 874 viewport.
2. Primary content on those pages does not require scrolling.
3. The four production captures each score at least 0.90 with
   `run-visual-parity.sh`.
4. Live production state still supplies counts, places, candidates, trips,
   stops, and actions; the deterministic fixture is launch-argument scoped.
5. Link capture, review candidate detail, saved place detail, Trip editing, and
   export remain reachable.
6. Generic iOS Simulator build exits 0.

## Failure fixture

Launch the review-demo UI with `--uitest-atlas-parity-fixture`. The fixture must
show:

- Home/Saves counts: 3 review, 18 Map Stamps, 2 failed.
- Saves tickets: Tsukiji Outer Market, Koffee Mameya, Yasaka Pagoda.
- Trip: Tokyo Weekend, three day tabs, four ordered stops.
- Root Map: Koffee Mameya selected in the compact inline place card.

The fixture never writes to production persistence or performs network calls.

## Xcode context receipt

- Product/repo: SAV-E / `wanderly-current`
- Platform: iOS
- Project: `SAV-E.xcodeproj`
- Scheme/target: `SAV-E` / `SAVE`
- Verification tier: build-only per iteration; UI at final gate
- Generic destination: `generic/platform=iOS Simulator`
- Runtime: one task-owned iOS 26.5 simulator for final screenshots only
- Simulator reason: four-screen production parity evidence
- Simulator lifecycle: final task-owned simulator shut down and deletion verified
- Deployment target: iOS 17.0
- Existing build command: `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build`
- Existing test command: focused `xcodebuild test` against `SAVEUITests`
- Canonical DerivedData: `$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- XcodeBuildMCP: unavailable; repo wrapper selected
- Touched surface: SwiftUI layout/navigation, local UI fixture, asset catalog
- Selected skill route: `swift-xcode-workflow` + `swiftui-view-refactor`
- Verification command: generic build, focused UI test, then four-page parity
- Skipped verification reason: none

## Security and privacy

N/A: local presentation code and repository-owned visual fixtures only. No
credentials, network endpoints, personal data, parser behavior, or storage
schema changes.

## Human boundary

Commit and PR are allowed after verification. Merge, deploy, TestFlight, App
Store submission, and any public asset-rights claim require separate approval.
