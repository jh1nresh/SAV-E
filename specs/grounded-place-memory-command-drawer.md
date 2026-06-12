# Grounded Place-Memory Command Drawer

> Created: 2026-06-11
> Repo: `wanderly-ios`
> Product: SAV-E / Wanderly
> Status: Product + implementation spec

## Goal

Upgrade SAV-E's drawer from a generic AI command box into a grounded place-memory command drawer.

MVP scope is narrower than the full future drawer: first prove fast saved-place search, lightweight recommendations, import/review/save, Map Stamps, open-in-maps, and sharing. AI itinerary planning is a future layer, not the first MVP promise. See `specs/save-mvp-place-search-share-scope.md`.

```text
Apple Maps search speed
+ personal memory grounding
+ lightweight recommendation judgment
+ evidence-safe save/share boundary
```

## Problem

The current drawer feels bad for search and place finding because it treats almost every input as an AI prompt.

Current behavior is roughly:

```text
User query
→ AIDrawerViewModel.submit()
→ SaveAIService.query(...)
→ AI JSON component
```

This creates several user-facing failures:

1. Simple place lookup feels slow and unintelligent.
2. Natural queries like `我今天想喝奶茶` do not reliably retrieve saved places.
3. Saved place memory is underused even though `Place` contains rich searchable fields.
4. Public place lookup exists through `GooglePlacesService`, but is not a normal drawer search path.
5. The drawer mixes search, AI planning, import, clue review, and venue resolution without making the mode clear.
6. `Find Venue` currently behaves like prompt injection into a text field instead of a dedicated place-resolution flow.

## Product principle

Do not make AI itinerary planning the first MVP promise, but do keep the architecture compatible with it later.

Also do not expose `Search mode` vs `AI mode` as two user-facing modes. The user should type naturally into one drawer input, and SAV-E should infer what they mean the way a good assistant does.

Use one drawer with an internal intent router:

```text
One drawer input
→ understand what the user is trying to do
→ retrieve grounded place context
→ decide internally whether this is recall, lightweight recommendation, public lookup, import/review, or future planning
→ render one state-aware answer/result
→ apply map action
```

Core rule:

```text
One input, one assistant surface.
Internal routing, not user-facing mode switching.
Search when the user is looking for a place.
Recommend from saved places when the user asks for judgment.
Keep full planning as a future layer.
Retrieve before generation.
Saved memory before public discovery.
Unsaved public candidates must stay clearly unsaved.
```

## Product model

```text
Map = spatial memory canvas
Drawer = intent + recommendation layer
Map Stamp = confirmed saved memory
Review Candidate = possible place with evidence, not confirmed memory
Nearby Unsaved Candidate = public map result, not saved memory
Lightweight Suggestion = ranked shortlist from saved memory
Future AI Plan = generated itinerary after the memory loop works
```

## User-facing behavior

### 1. Exact / fuzzy saved-place search

Example queries:

```text
Rise Bagels
that Irvine bagel place
UCI coffee
Omomo
```

Expected flow:

```text
query
→ local saved-memory search
→ review-candidate search
→ result sections
→ map highlights matched SAV-E-owned objects
```

Drawer result sections:

```text
From your SAV-E
Review candidates
Nearby unsaved candidates // only if user opted into public lookup
```

Expected UI:

- result title
- category / location / source
- reason for match
- state label: `Saved`, `Review candidate`, or `Unsaved`
- primary action

Example result:

```text
From your SAV-E
Rise Bagels
Cafe · Irvine · Google Maps import
Why: name match + saved address near Irvine
Primary: Open
Secondary: Plan around this
```

### 2. Intent recommendation over saved memory

Example queries:

```text
我今天想喝奶茶
I want boba today
coffee near UCI
適合約會的餐廳
something sweet after dinner
```

Expected flow:

```text
query
→ intent parse
→ local saved-memory search + category/synonym ranking
→ recommendation cards
→ optional AI explanation if ranking needs judgment
```

For boba / milk tea, include synonyms:

```text
奶茶
手搖
飲料
boba
bubble tea
milk tea
tea shop
tea
drink
```

Honest empty state:

```text
No saved milk-tea memories yet. Want SAV-E to look nearby?
```

Do not invent places.
Do not silently search public places and present them as saved memory.

### 3. AI planning from saved places

Example queries:

```text
幫我規劃 LA 兩天
用我收藏的咖啡廳做一個下午行程
幫我排一個 Irvine date night
把這幾個地方排成下午路線
```

Expected flow:

```text
query
→ intent router detects planning
→ retrieve relevant saved places first
→ pass retrieved context to AI planner
→ return itinerary / route / recommendation
→ map highlights or routes used places
```

AI answer must disclose grounding:

```text
Used 5 saved places.
Skipped 2 review candidates because they need confirmation.
No public places added.
```

If saved memory is insufficient:

```text
I only found one saved dinner spot near Irvine. Want me to look for nearby unsaved candidates to fill the plan?
```

### 4. Hybrid retrieval + planning

Example query:

```text
我今天想喝奶茶，順便排一個附近晚餐
```

Expected flow:

```text
1. Search saved boba / milk-tea memories.
2. Search saved dinner / food memories nearby.
3. If enough saved places exist, ask AI to rank/plan.
4. If missing a category, ask permission to public-search unsaved candidates.
```

Example drawer copy:

```text
I found 2 saved boba memories.
I don't have a saved dinner spot nearby yet.
Want SAV-E to look for nearby unsaved dinner candidates?
```

### 5. Public place lookup

Public lookup is allowed, but only through explicit user intent or confirmation.

Triggers:

```text
Look nearby
Find public candidates
Find this venue
Search outside my saved places
```

Flow:

```text
query
→ GooglePlacesService.searchPlace(query, near: current/visible region)
→ render Nearby unsaved candidates
→ user taps result
→ preview drawer
→ explicit Save / Review before saving
```

Rules:

- Public results are never Map Stamps until saved.
- Label them `Nearby unsaved candidates`.
- Use subdued map markers if shown.
- Require explicit save action before persistence.

### 6. Clue import / evidence flow

Import/link/screenshot/note flows remain in the drawer, but should not dominate the first search experience.

Structure:

```text
Top input: Search or plan from saved places
Primary result area: search/recommend/plan
Secondary area: Add clues / Import / Review Nest
```

`Find Venue` should not paste a long prompt into the text field. It should open a focused resolve-place flow:

```text
Find a place
[place idea input]
→ candidate cards with evidence
→ Review / Save
```

## Intent router

Add a lightweight deterministic router before calling AI.

Suggested enum:

```swift
enum DrawerIntent {
    case savedPlaceSearch(query: String)
    case savedMemoryRecommendation(query: String, intent: PlaceIntent)
    case aiPlanning(query: String, constraints: PlanningConstraints)
    case hybrid(query: String, intents: [PlaceIntent], planningGoal: PlanningGoal?)
    case publicPlaceLookup(query: String)
    case clueImport(query: String)
    case followUp(query: String)
}
```

Intent rules:

- Short proper-noun-like query → saved place search first.
- Query contains food/drink/category desire → saved-memory recommendation first.
- Query contains plan/route/day/trip/date/itinerary verbs → AI planning after retrieval.
- Query contains `nearby`, `outside saved`, `find public`, `look nearby` → public lookup allowed.
- Follow-up buttons or existing plan context → follow-up refinement.

## Retrieval before generation

Before AI planning, retrieve candidate context.

Current services:

```swift
SaveSearchController
SaveLocationIntentRecommendationService
```

Responsibilities:

- normalize query
- expand synonyms
- score saved places
- score review candidates when reliable
- group result sections
- produce reason strings
- produce map action

Search fields:

- `Place.name`
- `Place.address`
- `Place.note`
- `Place.extractedDishes`
- `Place.recommender`
- `Place.sourcePlatform`
- `Place.priceRange`
- `Place.category`
- review-candidate name/address/evidence fields where available

Ranking:

1. Exact name match
2. Name/address fuzzy match
3. Note/dish/recommender match
4. Intent synonym match
5. Category match
6. Confirmed saved Map Stamp boost
7. Reliable review candidate boost below saved places
8. Region/current-location/visible-map boost
9. Recency boost

## Drawer result model

Use a drawer-level model separate from raw AI JSON. The current app model is
`SaveSearchResponse`, with `fromYourSave`, review/additional sections,
`newRecommendations`, `followUpChoices`, `resolvedAgentAnswer`, and
`MapActionData`.

Earlier drafts used this shape:

```swift
struct DrawerCommandResult: Equatable {
    var title: String
    var subtitle: String?
    var sections: [DrawerResultSection]
    var plan: DrawerPlanResult?
    var groundingReceipt: GroundingReceipt?
    var mapAction: MapActionData?
}

struct DrawerResultSection: Equatable {
    var title: String
    var state: DrawerSectionState
    var items: [DrawerResultItem]
}

struct DrawerResultItem: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var reason: String?
    var stateLabel: String
    var source: DrawerResultSource
    var primaryAction: DrawerAction
    var secondaryActions: [DrawerAction]
}

enum DrawerResultSource: Equatable {
    case savedPlace(UUID)
    case reviewCandidate(UUID)
    case publicCandidate(String) // Google place id
}
```

Grounding receipt:

```swift
struct GroundingReceipt: Equatable {
    var savedPlaceCount: Int
    var reviewCandidateCount: Int
    var publicCandidateCount: Int
    var skippedReason: String?
    var copy: String
}
```

Example receipt copy:

```text
Used 5 saved places. Skipped 2 review candidates with weak evidence. No public places added.
```

## UI requirements

### Input placeholder

Replace:

```text
Ask about your places...
```

With one of:

```text
Search or plan from your saved places...
Ask SAV-E where to go...
```

### Suggested chips

Use chips as examples/shortcuts, not as hard modes or tabs. The drawer must still infer intent from the text if the user types naturally.

```text
Search saved places
Plan a day
Find boba
Review clues
Import a link
```

These chips should only prefill or trigger common intents. They should not make the user choose between `search` and `AI` before typing.

### Result display

Always prefer structured sections over a generic AI paragraph.

Section examples:

```text
From your SAV-E
Planning answer
Review candidates
Nearby unsaved candidates
```

### State labels

Use consumer-facing labels:

```text
Saved
Review candidate
Not saved yet
Needs evidence
Used in plan
```

Avoid engineering labels:

```text
sourceOnly
unsaved candidate
mapVisibleUnsavedPlace
```

## Map behavior

- Saved-place results: filter/highlight actual saved pins.
- Planning results: show route or highlight used saved places.
- Review candidates: only highlight if coordinates are reliable; otherwise show in drawer only.
- Public candidates: may show temporary/subtle markers, but not as SAV-E Map Stamps.
- Reset should restore all saved pins.

## Implementation plan

### PR 1 — local saved-memory search + recommendation

Files likely touched:

- `SAV-E/Services/SaveSearchController.swift`
- `SAV-E/Services/SaveLocationIntentRecommendationService.swift`
- `SAV-E/ViewModels/AIDrawerViewModel.swift`
- `SAV-E/Models/SaveSearchModels.swift`
- `Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift`
- `Tests/SocialPlacePipelineTests/SaveLocationIntentRecommendationServiceTests.swift`

Acceptance:

- `Rise Bagels` finds saved place by name.
- `我今天想喝奶茶` matches saved boba/milk-tea places through synonyms.
- No saved result returns an honest empty state.
- No Gemini/API key required.
- MapAction filters matched saved pins.

### PR 2 — structured drawer result UI

Files likely touched:

- `SAV-E/Views/Drawer/AIDrawerView.swift`
- new drawer result components if needed
- `AIDrawerViewModel.swift`

Acceptance:

- Drawer shows sections instead of only AI message components.
- Results explain why each place matched.
- Saved/review/unsaved states are visually distinct.
- Import/clue tools remain accessible but no longer dominate search UX.

### PR 3 — AI planning with retrieval receipt

Files likely touched:

- `SaveAIService.swift`
- `AIDrawerViewModel.swift`
- result model/UI

Acceptance:

- Planning queries retrieve saved places before generation.
- AI prompt receives only relevant place context plus constraints.
- Output includes grounding receipt copy.
- If memory is insufficient, user is asked whether to search public candidates.

### PR 4 — public find-place flow

Files likely touched:

- `GooglePlacesService.swift` if needed
- `MapViewModel.swift`
- drawer result UI
- temporary candidate map rendering if included

Acceptance:

- Public lookup appears as `Nearby unsaved candidates`.
- Public candidates require explicit save/review before becoming Map Stamps.
- No public candidate is persisted automatically.

## Tests

Add focused tests before broad UI work where possible.

Recommended test cases:

1. Exact saved-place name search.
2. Fuzzy address/name search.
3. Note/dish/recommender search.
4. Chinese boba intent: `我今天想喝奶茶`.
5. English boba synonyms: `boba`, `milk tea`, `bubble tea`.
6. Empty saved-memory fallback.
7. Ranking: saved place above review candidate above public candidate.
8. Planning intent routes through retrieval before AI.
9. Public candidate cannot become saved without explicit save action.
10. MapAction filters saved places only for saved-memory results.

## Verification

Use the Swift/Xcode workflow before engineering work.

Expected commands:

```bash
xcodebuild test -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEOnboardingSE,OS=26.5' -only-testing:SAVETests/<NewSearchOrDrawerTests> CODE_SIGNING_ALLOWED=NO
xcodebuild build -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEOnboardingSE,OS=26.5' CODE_SIGNING_ALLOWED=NO
~/brain/scripts/brain containment check --strict
```

If the simulator/device name differs, record the actual destination in the engineering receipt.

## Non-goals

- No new AI tab.
- No generic chatbot surface.
- No silent public discovery.
- No auto-saving public places.
- No order/reservation/payment flow.
- No full trip planner rewrite.
- No backend migration in the first PR.
- No claim that public Google/Apple Maps results are SAV-E memory.

## Success criteria

The drawer succeeds when these all feel true:

1. Typing a place name feels as fast and predictable as a map search.
2. Asking a natural intent like `我今天想喝奶茶` searches SAV-E memory first.
3. Asking for a plan uses AI, but the AI visibly grounds itself in saved places.
4. Public candidates are useful but clearly not saved memory.
5. The user can understand what SAV-E used, skipped, and needs confirmed.

## One-line product spec

```text
SAV-E's drawer is a grounded place-memory command drawer: fast search when the user is looking for a place, AI planning when the user asks for judgment, and hybrid retrieval-planning when the query needs both.
```
