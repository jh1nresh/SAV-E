# Origin tab → Plan v0

Status: implementation brief
Completes: replace the Origin root tab with a Plan workbench that
drafts itineraries from confirmed Map Stamps, then offers unsaved
attractions as labeled Trip Stops.

## Paid user job / observed failure

A traveler opens Savvy to turn their own Map Stamps into a day they can
walk. Origin occupied a permanent tab with a social swipe deck that
needs other people's shares. Trip planning lived as a Beta child route
and a chat draft whose times were category heuristics (cafe at 9:00,
lunch at 12:30) with no arrival, lodging, or meal-window contract.

## Acceptance criteria

1. Root bar order is exactly:

   ```text
   [ Home ]  [ Map ]  ( + Save )  [ Plan ]  [ Profile ]
   ```

2. Plan is the destination. It is not a social feed. Capture remains a
   raised control. Origin is no longer a root tab.

3. Plan drafts from confirmed Map Stamps in a chosen city/area. Public
   or unsaved suggestions are `externalSuggestion` / Unsaved Candidate,
   never silent Map Stamps, and are excluded from "Save as Trip" until
   the user confirms them through the normal save path.

4. Time is a contract, not a costume:
   - meals occupy breakfast / lunch / dinner windows and do not stack
   - a saved stay becomes check-in on day 1 and check-out on the last day
   - optional arrival / departure clocks shrink the usable day
     (airport buffer after landing, airport transfer before takeoff)
   - Savvy does not book flights or hotels

5. Five-second state test: a Map Stamp, an Unsaved Candidate, and a
   lodging/travel window are visually distinct on the Plan canvas.

## Failure fixtures

- Root bar still exposing Origin as a tab.
- Unsaved attraction persisted as a Map Stamp without confirmation.
- Invented flight or hotel booking.
- Two meals in the same window, or a last-day stop after the departure
  buffer.
- A stay scheduled as a mid-day tourist stop.

## Classification

Feature. Root-bar job swap plus itinerary rhythm on the existing Atlas
Plan / Trips faces.

## Demand, pricing, first distribution

- Demand proof: founder lock after comparing Origin vs trip planning.
  Origin as a social deck is a later loop; Plan is the last step of
  `Source Clue → Review Candidate → Map Stamp → Trip Plan`.
- Pricing / paywall hypothesis: unchanged. Plan stays free during Beta.
  No booking, StoreKit, or entitlement change.
- First distribution: one PR against current `main`. No merge, no
  TestFlight, no App Store Connect, no Railway / Vercel from this packet.

## Files and systems in scope

- `SAV-E/App/ContentView.swift` (`SaveRootTab`, Plan destination)
- `SAV-E/Views/Plan/SavePlanView.swift`
- `SAV-E/Services/SaveDayRhythmScheduler.swift`
- `SAV-E/Services/SavePlanDraftBuilder.swift`
- `SAV-E/Models/AIResponse.swift` (day window note, lodging gap)
- `DESIGN.md` vocabulary / tab jobs
- Tests: Atlas five-tab, rhythm scheduler, screenshot rail tab names

Out of scope: real flight/hotel booking, TREK vendoring, Origin capture
model deletion, StoreKit, schema, Railway.

## Verification

```bash
# CI: SAVETests AtlasFiveTabBarTests + SaveDayRhythmSchedulerTests
# CI UI rail must include five-tab-plan in place of five-tab-origin
```

## Security and privacy

No new location, account, or purchase data. Unsaved candidates stay
owner-local suggestions. Private clues never publish. The client does
not grant Pro and does not call booking providers.

## Human approval still required

Merge, production secrets / schema, Railway or Vercel, signing, App
Store Connect, TestFlight, any future booking provider.
