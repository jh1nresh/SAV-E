# SAV-E Map Search + Intent Recommendations Spec

> Status: Proposed next optimization
> Date: 2026-05-25
> Owner: JhiNResH
> Source: product critique from map/card dogfood session
> Related PR context: memory card redesign + Map Stamp pin redesign in PR #157

## Blunt product call

SAV-E cannot make the map feel alive if the user can only tap already-saved pins.

Current problem:

```text
User opens map
→ sees saved pins and default map POIs
→ cannot search a place directly on the map
→ cannot ask natural intent like “我今天想喝奶茶”
→ map feels passive / broken / less useful than Apple Maps
```

The next optimization should make the drawer the intent layer over the user's saved place memory:

```text
I want milk tea today
→ SAV-E searches my saved memories first
→ ranks relevant tea/boba/cafe/dessert places
→ highlights pins on the map
→ explains why each place fits
→ offers next actions: Navigate, Plan around this, Save nearby candidate
```

This is not a generic travel-search feature. It is the first proof that SAV-E's saved places become an agent-readable memory graph.

## Product principle

```text
Map = spatial memory canvas
Drawer = intent + recommendation layer
Map Stamp = confirmed memory
Recommendation = contextual answer over memory
Unsaved candidate = clearly labeled, never mixed into memory
```

SAV-E should answer user intent from their own memory before going to the public map.

## User jobs

### 1. Explicit place search

User wants to find a known saved place or candidate:

```text
“Rise Bagels”
“UCI coffee”
“that Irvine bagel place”
```

Expected behavior:

```text
Search saved places + review candidates
→ show matching SAV-E results
→ highlight matching pins
→ tap result opens drawer/card
```

### 2. Intent recommendation

User wants a decision, not a search result:

```text
“我今天想喝奶茶”
“I want boba today”
“coffee near my saved places”
“dessert after dinner”
```

Expected behavior:

```text
Classify intent
→ search SAV-E saved places first
→ rank by fit
→ return recommendation card
→ highlight relevant pins
```

### 3. Empty-memory fallback

If there are no saved places that match:

```text
SAV-E should not hallucinate.
```

Expected behavior:

```text
No saved milk-tea memories yet.
Want SAV-E to look for nearby candidates?
```

If public discovery is implemented, results must be labeled:

```text
Nearby unsaved candidates
```

not:

```text
Map Stamps
```

## V0 scope

Build V0 as local-first and saved-memory-first.

### In scope

- Add map/drawer search mode that can filter and highlight saved places.
- Add simple intent parsing for common food/drink intents.
- Add synonym matching for food, cafe, dessert, milk tea/boba/tea/coffee.
- Add result sections:
  - `From your SAV-E`
  - `Review candidates`
  - optional future `Nearby unsaved candidates`
- Add a recommendation result card with reasoning:
  - why it matched
  - where it came from
  - confidence / evidence source if available
  - next action
- Use existing `MapActionData.filterPins` / `focusRegion` where possible.
- Keep all unsaved public-map results out of `Place` persistence unless explicitly saved.

### Out of scope

- Full public place search index.
- Logged-in social scraping.
- Fake map pins for source-only clues.
- Automatic save from recommendation.
- Payment, reservations, order placement, or coupons.
- New AI tab.
- Broad backend schema migration.

## Current code context

Relevant files inspected:

```text
Wanderly/Views/Map/MapView.swift
Wanderly/ViewModels/MapViewModel.swift
Wanderly/Views/Drawer/AIDrawerView.swift
Wanderly/ViewModels/AIDrawerViewModel.swift
Wanderly/Services/WanderlyAIService.swift
```

Current behavior:

- `MapView` renders saved places from `viewModel.filteredPlaces` as tappable annotations.
- `MapViewModel` has `reviewCandidates` and `reviewCandidatesOnMap`, but map search is not the primary user flow.
- `AIDrawerView` already has a query field and submit behavior.
- `AIDrawerViewModel.submit()` sends the query to `WanderlyAIService` with saved places.
- `WanderlyAIService.localIntentResponse` only handles coarse English category commands such as food/cafe/bar/attraction when query contains `show/map/spots/places`.
- The AI prompt says it can use saved places and create lists/itineraries, but the product does not yet feel like map-native search/recommendation.

This means the right V0 is not a new page. It should extend the existing drawer + map action loop.

## Proposed UX

### Search placeholder

Current placeholder can remain conversational, but should make the map/search affordance explicit.

Suggested copy:

```text
Ask or search your places…
```

Examples under the drawer:

```text
I want boba today
Coffee near Irvine
Show saved desserts
Plan around this Map Stamp
```

### Intent result: milk tea

Input:

```text
我今天想喝奶茶
```

If saved relevant places exist:

```text
Title: Milk tea from your SAV-E
Message: I found 3 saved memories that fit milk tea / boba / tea today.

Cards:
1. Sunright Tea Studio
   Why: saved as cafe + note/source mentions boba / tea
   Action: Navigate
   Secondary: Plan around this

2. Omomo Tea Shoppe
   Why: saved near Irvine and tagged cafe/dessert
   Action: Navigate
   Secondary: View source
```

Map behavior:

```text
filterPins(relevantPlaceIds)
selected/first result focused if high confidence
```

If no saved relevant places exist:

```text
Title: No milk tea memories yet
Message: I couldn't find saved tea/boba places in your SAV-E.
Primary: Search nearby candidates
Secondary: Paste a place link
```

Public candidates, if implemented later:

```text
Nearby unsaved candidates
- clearly different pin style
- not Map Stamp
- Save this place action required
```

## Ranking rules

For V0 deterministic/local ranking:

1. Exact text match in name/address/notes/source summary.
2. Synonym match:
   - milk tea, boba, bubble tea, tea shop, tea, drink
   - coffee, cafe, espresso, matcha
   - dessert, bakery, sweets
3. Category match:
   - cafe > food > shopping for drink intent
4. Status boost:
   - saved/Map Stamp > review candidate > source-only clue
5. Context boost:
   - selected map region or current location if available
   - recently saved if no location context
6. Evidence boost:
   - source/note explicitly says boba/milk tea
   - confirmed address/coordinates

Do not rank source-only clues as map-ready unless they have reliable coordinates.

## Data model / service shape

Add a local search/recommendation layer before hitting the LLM:

```swift
struct SaveIntentQuery {
    enum Kind {
        case explicitPlaceSearch
        case craving
        case category
        case tripPlanning
        case unknown
    }

    let rawText: String
    let normalizedTerms: [String]
    let kind: Kind
    let targetCategories: [PlaceCategory]
}
```

```swift
struct SaveRecommendationResult {
    let place: Place
    let score: Double
    let reasons: [String]
    let evidenceLabel: String?
}
```

Possible service:

```text
SaveIntentRecommendationService
```

Responsibilities:

```text
parse query
→ score saved places
→ score review candidates if coordinates/evidence exist
→ return sections + map action
```

## Integration plan

### PR A — Saved-memory map search

Files likely touched:

```text
Wanderly/Services/SaveIntentRecommendationService.swift
Wanderly/ViewModels/AIDrawerViewModel.swift
Wanderly/Services/WanderlyAIService.swift
Wanderly/Views/Drawer/AIDrawerView.swift
WanderlyTests/SaveIntentRecommendationServiceTests.swift
```

Acceptance:

- Query `Rise Bagels` returns matching saved place.
- Query `I want coffee` returns cafe/coffee saved places.
- Query `我今天想喝奶茶` maps to tea/boba/cafe intent.
- Result uses `MapActionData.filterPins` for matched saved place ids.
- No Gemini/API key required for deterministic saved-memory search.

### PR B — Recommendation card UI

Files likely touched:

```text
Wanderly/Models/WanderlyAIResponse.swift
Wanderly/Views/Drawer/AIDrawerView.swift
Wanderly/Views/Map/MapView.swift
```

Acceptance:

- Drawer renders recommendation cards with `why this fits` reasons.
- Primary action is `Navigate` or `Plan around this`.
- Result sections distinguish `From your SAV-E` from non-saved candidates.
- Recommended pins visually highlight without pretending default POIs are interactive.

### PR C — Optional nearby unsaved candidates

Only after A/B work.

Files likely touched:

```text
Wanderly/Services/MapPlaceSearchService.swift
Wanderly/ViewModels/MapViewModel.swift
Wanderly/Views/Map/MapView.swift
```

Acceptance:

- Uses `MKLocalSearch` or existing Google Places adapter to fetch nearby candidates.
- Unsaved candidates use separate marker style.
- Tapping unsaved candidate opens `Save this place` drawer, not memory card.
- Source-only/no-coordinate clues never become fake pins.

## Acceptance criteria for the full optimization

- User can search saved places from the map drawer.
- User can ask `我今天想喝奶茶` and receive saved-memory recommendations if available.
- If no matching saved memories exist, SAV-E says so honestly.
- Map highlights SAV-E-owned objects only; default POIs do not pretend to be app markers.
- Recommendations explain why they fit.
- Unsaved public candidates, if shown, are explicitly labeled unsaved and require confirmation before becoming Map Stamps.
- No new AI tab.
- No hallucinated places or coordinates.

## Verification plan

Minimum local checks:

```bash
xcodebuild test -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' -only-testing:WanderlyTests/SaveIntentRecommendationServiceTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
/Users/jhinresh/brain/scripts/brain containment check --strict
```

Manual smoke:

```text
Open map
→ ask “我今天想喝奶茶”
→ relevant saved milk-tea/cafe pins highlight
→ tap a recommendation
→ drawer opens memory card / action card
→ Navigate works
```

## Why this is the next right optimization

The user criticism is correct: a map with ugly/passive pins and no search cannot compete with default maps.

SAV-E's advantage should be:

```text
not “I can show places”
but “I understand what your saved places are useful for right now.”
```

Milk tea is the right test case because it is concrete, everyday, and intent-shaped. If SAV-E can answer that from saved memories, the product starts feeling like a private place agent instead of a saved-pin viewer.
