# SAV-E One Job Per Tab v0

Status: implementation brief
Complements: Atlas One-Face UI v0, `Prototypes/AtlasPostcard/design.md`
Palette: production `SaveAtlasPalette` on main. Canvas `#FDF8F3`, forest `#0E4A33`,
coral `#F26B4A`, sky `#B5E3F5`, ink `#2E2117`, muted `#62594F`. This is a
density / information-architecture change, not a restyle.

## Paid user job / observed failure

A traveler opens SAV-E to do one thing on the tab they tapped. After One-Face,
Home still stacked Review, a Continue-today trip strip, two stat columns, and
recent Map Stamps. Review still opened like a form. Passport put language and
Pro next to Memo Book. The first screen asked for too many decisions.

## Acceptance criteria

1. Each root tab has one job, one primary object, and one coral control or none.
2. Home is one-city atlas plus exactly one sheet.
   - If `reviewCount > 0`: Review clues only (coral).
   - Else if a same-city trip exists: that trip sheet, no coral.
   - Else: quiet empty.
   - No stamps list, no Continue today section, no two stat columns, no second
     city. Stamps live on Saves Map Stamps. The trip strip lives on Trips.
3. Saves shows one pocket face at a time (Review or Map Stamps). The first
   viewport holds at most three tickets plus the envelope mouth. Capture is the
   only coral.
4. Trips shows one featured trip, at most one secondary ticket, Beta visible,
   and does not scroll.
5. Map at rest is live MapKit plus one cream shelf. No default place card.
6. Review / Postcard is a ticket, not a form. First viewport: paper, title,
   source line, seal, Memo peek, coral Confirm. Map crop, MAP READY, 84%,
   Next Step essay, name field, and More actions sit below the first viewport.
7. Passport opens on Memo Book. Language and Pro sit behind a disclosure.
8. The app may observe a purchase. Only the server may grant one. No Pro or
   paywall on Home, Saves, Review, Map, or first-run.

Failure fixtures:

- Home with review > 0 still showing stamps, trip strip, or two stat columns.
- Home with Taipei atlas pairing Tokyo Weekend.
- Review first viewport showing MAP READY, 84%, Next Step, name field, or
  More actions.
- Any grant-path edit in `SaveEntitlementStore` or
  `serverVerifiedTier ?? locallyObservedTier`.

## Classification

Feature. Density / IA on existing Atlas and Postcard faces.

## Demand, pricing, first distribution

- Demand proof: founder lock after One-Face. Home still felt like a dashboard.
- Pricing / paywall hypothesis: core place memory stays free. Pro stays off
  Home / Saves / Review / Map / first-run. Passport settings disclosure only.
- First distribution: draft PR against main. No merge, no Judge, no TestFlight,
  no App Store Connect, no Railway / Vercel.

## Files and systems in scope

- `Prototypes/AtlasPostcard/Sources/Presentation.swift`
- `Prototypes/AtlasPostcard/Sources/Screens.swift`
- `Prototypes/AtlasPostcard/design.md` (Home / Trips / Map rest IA only)
- `SAV-E/Views/Home/SaveRootViews.swift`
- `SAV-E/Views/Atlas/SaveAtlasProductionBridge.swift`
- `SAV-E/Views/Drawer/AIDrawerView.swift`
- `SAV-E/Views/Profile/ProfileView.swift`
- `Tests/SocialPlacePipelineTests/AtlasOneJobPerTabUITests.swift`
- `Tests/SAVEUITests/SAVEScreenshotRailTests.swift`

Out of scope: StoreKit products and prices, entitlement enforcement, schema,
Railway, App Store listing, Clip header, Clip Swift, Slice 3, PR #142 residual
(`serverVerifiedTier ?? locallyObservedTier` / `SaveEntitlementStore`), PR #150
icon work, Expo / React Native.

## Verification

iOS-safe unit tests only. No `Process()`, no `git diff`, no simulator boot for
this packet.

```bash
# CI canonical checker: SAVETests AtlasOneJobPerTabUITests
# Local generic compile remains the ordinary iOS gate when Xcode is present.
```

## Security and privacy

No new location, account, or purchase data. Home still reverse-geocodes in
memory only. Review confirmation semantics stay user-confirmed. The client
does not grant Pro.

## Human approval still required

Merge, production secrets / schema, Railway or Vercel, signing, App Store
Connect, TestFlight, Judge assignment.

## Locked tab jobs

```text
Home  = one city atlas + one sheet
Saves = one pocket face (Review or Map Stamps)
Trips = one featured trip + at most one secondary ticket
Map   = live MapKit + cream shelf at rest
```
