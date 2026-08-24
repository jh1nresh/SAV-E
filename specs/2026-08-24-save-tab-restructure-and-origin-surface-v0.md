# SAV-E five-tab restructure and Origin surface v0

Status: implementation brief (W2/W3 landed; W4 placeholder only; W5 unstarted)
Complements: `specs/2026-08-23-save-one-job-per-tab-v0.md`,
`Prototypes/AtlasPostcard/design.md`
Palette: production `SaveAtlasPalette`. This is a root-bar and Home IA change,
not a restyle.

Cited by `SAV-E/App/ContentView.swift`,
`SAV-E/Views/Origin/SaveOriginPlaceholderView.swift`, and
`Tests/SocialPlacePipelineTests/AtlasFiveTabBarTests.swift`.

## Paid user job / observed failure

A traveler opens the app to do one thing on the tab they tapped. The four-tab
bar spent two permanent slots on Saves and Trips. Capture lived as a Home
top-right Paste action and as a Saves coral, so the first screen still asked
for two jobs. Origin (where a saved place came from) had no honest home.

The four-item selection pill was a hardcoded 90pt against a ~98.5pt slot. A
fifth item makes the slot ~78.8pt, so that pill overflows its neighbors.

## Acceptance criteria

### W2 — five-tab root bar

1. Root bar order is exactly:

   ```text
   [ Home ]  [ Map ]  ( + Save )  [ Origin ]  [ Profile ]
   ```

2. `Save` is a raised centre control, not a destination. Selecting it opens the
   capture cover and leaves the previous tab selected.
3. Saves is gone from the root bar. `SaveLibraryView` remains a pushed child
   (`SaveRootRoute.saves`) so Review / Manage still have a real surface.
4. Trips is demoted off the root bar. It stays reachable from Home and from a
   place (`SaveRootRoute.trips`). Demoting a tab must not delete the feature.
5. Home is the clean memory surface: confirmed saved places render immediately.
   Manage opens the Saves child. Review appears only when pending items exist.
   Home does not expose a top-right Paste-a-link action; the centre Save tab is
   the single capture entry.

### W3 — one icon set, adaptive pill

1. `SaveRootTab` exposes exactly one icon property: `atlasIcon`.
   Do not reintroduce `systemImage`.
2. Glyphs are distinct and Atlas-language: Home `book.closed`, Map `map`
   (not a globe), Save `plus`, Origin `paperclip`, Profile `person.crop.circle`.
   No briefcase. No globe.
3. `AtlasTabBarMetrics` derives pill width from slot width. The pill must fit
   at four and five items. The legacy 90pt pill is documented as the
   five-item overflow fixture.

### W4 — Origin (placeholder only)

Origin's job is: *where did this place come from* — the user's own capture,
quoted verbatim with its original link. It is not a social feed.

This packet lands `SaveOriginPlaceholderView` so the five-tab shape is real
and testable. The placeholder is an honest empty state. Do not add sample
data, seeded cards, or copy that implies other users (`people saved`,
`friends`, `trending`, `popular`, `nearby saved`). W4 content must be built
against real captures.

### W5 — unstarted

Origin content, source-clip playback, and any later social-adjacent surface
are out of this packet.

## Failure fixtures

- Root bar still exposing Saves or Trips as tabs.
- Capture committed as a selected destination instead of a cover.
- Home missing confirmed saved places, or still showing a decorative regional
  hero / Home Paste action.
- Selection pill overflowing its slot at five items.
- Origin copy implying other users or seeded social proof.
- Any grant-path edit in `SaveEntitlementStore` other than the shipped
  qualified form `storeKit.serverVerifiedTier ?? storeKit.locallyObservedTier`.
- Any change to `com.wanderly.*` bundle IDs, App Group, team, associated
  domains, or StoreKit product IDs.

## Classification

Feature. Root-bar topology and Home IA on the existing Atlas / Postcard faces.

## Demand, pricing, first distribution

- Demand proof: founder lock after One Job Per Tab. Four tabs still hid
  capture and spent permanent slots on low-frequency surfaces.
- Pricing / paywall hypothesis: unchanged. The client may observe a purchase.
  Only the server may grant one. No Pro or paywall on Home, Map, Origin,
  capture, or first-run.
- First distribution: one PR against current `main` that also carries One Job
  Per Tab and the Savvy public rename. No merge, no Judge, no TestFlight, no
  App Store Connect, no Railway / Vercel from this packet.

## Files and systems in scope

- `SAV-E/App/ContentView.swift` (`SaveRootTab`, root routing, raised Save)
- `SAV-E/Views/Origin/SaveOriginPlaceholderView.swift`
- `SAV-E/Views/Home/SaveRootViews.swift` (Home saved-place library)
- `SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift`
- `Prototypes/AtlasPostcard/Sources/{Components,Presentation,Screens}.swift`
- `Tests/SocialPlacePipelineTests/AtlasFiveTabBarTests.swift`
- `Tests/SAVEUITests/SAVEScreenshotRailTests.swift` (`testCaptureFiveTabLanding`
  and Saves/Trips root-tab migrations)

Out of scope: StoreKit products and prices, entitlement enforcement, schema,
Railway, App Store listing bytes beyond the Savvy rename packet, RelatedPlace
source-pack / #153 map slice, archive / TestFlight.

## Verification

```bash
# CI: SAVETests AtlasFiveTabBarTests + AtlasOneJobPerTabUITests
# CI UI rail must include:
#   SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding
# Local generic compile remains the ordinary iOS gate when Xcode is present.
```

Atlas / five-tab visual rasters (`Prototypes/AtlasPostcard/Reference/Targets`)
must match the five-tab Home / Map / Plan / Saves-from-Home faces or the
`run-visual-parity.sh` gate fails. A live reshoot needs an iOS simulator.
The Home target comes from `testCaptureFiveTabLanding`'s `five-tab-home`
attachment so the gate proves the live saved-place library, not the locked
One-Face parity fixture.

## Security and privacy

No new location, account, or purchase data. Origin must not fabricate other
users. Review confirmation semantics stay user-confirmed. The client does not
grant Pro.

## Human approval still required

Merge, production secrets / schema, Railway or Vercel, signing, App Store
Connect, TestFlight, Judge assignment.

## Locked tab jobs after this packet

```text
Home    = confirmed saved places + Manage / Review / Trips as child routes
Map     = live MapKit + cream shelf at rest
Save    = raised capture control (not a tab destination)
Origin  = honest placeholder until W4
Profile = Memo Book first (One Job) / passport
```
