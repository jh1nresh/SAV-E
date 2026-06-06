# Ask SAV-E Location + Intent Agent Spec

> Status: PM/spec-only handoff
> Date: 2026-05-26
> Owner: JhiNResH
> Source: dogfood critique — Ask SAV-E recommends wrong categories and non-nearby saved places for queries like `附近咖啡廳`
> Related specs: `specs/2026-05-25-save-map-search-intent-recommendations.md`, `specs/2026-05-26-memory-first-command-drawer.md`

## Blunt product call

Ask SAV-E currently feels unintelligent because it does not enforce the two constraints users assume are mandatory:

```text
nearby query -> distance gate
category query -> category gate
```

The model/provider is not the root problem. The root problem is that SAV-E lets a language model or broad saved-memory search produce answers before the app has built a safe structured retrieval contract.

Wrong behavior observed / reported:

```text
User asks: 附近咖啡廳
SAV-E recommends:
- saved places that are not near the user's current location
- wrong categories such as gyms
- places outside the asked category or outside the current area
```

Correct product behavior:

```text
If the user's SAV-E has nearby saved cafes -> recommend only those.
If cafes exist but not nearby -> say they are saved but not nearby.
If nearby saved places exist but are not cafes -> do not recommend them.
If no saved nearby cafe exists -> say so honestly and offer public nearby search.
```

This is the trust line:

```text
No result is better than a wrong-category or wrong-location recommendation.
```

## Product principle

```text
Ask SAV-E = bounded local place-memory agent
LLM = intent parser + explanation layer
Deterministic code = geo/category/source gating
Public map search = explicit fallback, never mixed with memory
```

Do **not** build this as a generic travel chatbot or a new AI tab. It should live inside the current drawer/search loop.

## Existing code context

Files already relevant:

```text
SAV-E/Services/SaveAIService.swift
SAV-E/Services/SaveSearchController.swift
SAV-E/ViewModels/AIDrawerViewModel.swift
SAV-E/Views/Drawer/AIDrawerView.swift
SAV-E/Models/AIResponse.swift
SAV-E/Models/Place.swift
```

Current implementation facts:

- `SaveAIService` uses Gemini via `GEMINI_API_KEY`.
- Current model fallback order is centralized in `SAVEProductionConfig.defaultGeminiModelFallbacks` and starts with `gemini-3.5-flash`.
- `SaveAIService.localIntentResponse` only handles coarse category commands when the query contains English trigger words like `show`, `map`, `spots`, or `places`.
- `SaveSearchController` already has early intent/category parsing for terms such as milk tea, coffee, food, bar, attraction, and stay.
- `SaveSearchController` currently ranks local and unsaved map candidates but does not have a strict current-location distance gate for `nearby` queries.
- `Place` has non-optional `latitude`, `longitude`, and `category`, so confirmed Map Stamps can be deterministically filtered by category + distance.

## Target state machine

```text
User query
-> SearchIntent
-> candidate retrieval
-> hard gates
-> ranked sections
-> grounded answer
-> map action
```

Detailed:

```text
raw text
-> normalize multilingual query
-> parse intent/category/location mode/radius/public fallback policy
-> search confirmed Map Stamps first
-> optionally include Review Candidates only when coordinates + category confidence are reliable
-> exclude wrong category and wrong distance from primary recommendations
-> produce honest empty state when nothing matches
-> offer explicit Nearby Unsaved Candidates fallback
```

## SearchIntent contract

Add a first-class query object. It can be populated deterministically first, with an LLM fallback only when deterministic parsing is uncertain.

```swift
struct SaveSearchIntent: Equatable {
    enum Kind: Equatable {
        case explicitPlaceSearch
        case categoryRecommendation
        case craving
        case tripPlanning
        case publicDiscovery
        case unknown
    }

    enum LocationMode: Equatable {
        case currentLocation(radiusMeters: Double)
        case mapRegion
        case namedArea(String)
        case savedAnywhere
        case unspecified
    }

    enum SourceScope: Equatable {
        case savedOnly
        case savedFirstAllowPublicFallback
        case publicOnly
    }

    let rawText: String
    let normalizedText: String
    let kind: Kind
    let requiredCategories: Set<PlaceCategory>
    let optionalCategories: Set<PlaceCategory>
    let locationMode: LocationMode
    let sourceScope: SourceScope
    let mustMatchCategory: Bool
    let mustMatchLocation: Bool
    let confidence: Double
}
```

Default radius:

```text
nearby / near me / 附近 / around here -> 2,000m default
walking-ish query -> 1,000m
city / area query -> named-area match, not current-location gate
no location phrase -> savedAnywhere
```

Category examples:

```text
咖啡廳 / cafe / coffee -> requiredCategories = [.cafe]
奶茶 / boba / bubble tea / tea shop -> requiredCategories = [.cafe], optional text needles include tea/boba/milk tea
晚餐 / lunch / restaurant / 餐廳 -> requiredCategories = [.food]
健身房 / gym -> currently unsupported PlaceCategory; should not satisfy cafe/food intent
```

If a requested category has no supported `PlaceCategory`, return an honest unsupported-category message rather than mapping it to a random category.

## Result sections

Return separate sections, never one blended list:

```text
From your SAV-E nearby
Saved but not nearby
Review candidates nearby
Nearby unsaved candidates
Unsupported / no match
```

Rules:

- `From your SAV-E nearby`: confirmed saved Map Stamps satisfying category and location gates.
- `Saved but not nearby`: same category, outside radius. Mention as context; do not primary-recommend.
- `Review candidates nearby`: only if coordinates exist and category/evidence matches; still labeled unconfirmed.
- `Nearby unsaved candidates`: public map results only after explicit fallback action.
- `Unsupported / no match`: honest empty state when no result passes the gates.

## P0 — Stop bad recommendations

### Goal

Prevent trust-breaking answers immediately.

### Scope

Add strict gates before any answer can recommend places for nearby/category queries.

### Implementation direction

Likely files:

```text
Create: SAV-E/Services/SaveSearchIntentParser.swift
Create: SAV-E/Services/SaveLocationIntentRecommendationService.swift
Modify: SAV-E/Services/SaveSearchController.swift
Modify: SAV-E/Services/SaveAIService.swift
Modify: SAV-E/ViewModels/AIDrawerViewModel.swift
Test: SAVETests/SaveLocationIntentRecommendationServiceTests.swift
```

Core logic:

```swift
if intent.mustMatchCategory {
    candidates = candidates.filter { intent.requiredCategories.contains($0.category) }
}

if intent.mustMatchLocation {
    guard let currentLocation else {
        return .needsCurrentLocationPermission(intent)
    }
    candidates = candidates.filter { distanceMeters(currentLocation, $0.coordinate) <= radius }
}
```

Acceptance criteria:

```text
Given currentLocation = X
And saved places:
- Cafe A, category=cafe, 1km away
- Gym B, category=unsupported/gym or non-cafe, 0.3km away
- Cafe C, category=cafe, 20km away

When user asks: 附近咖啡廳
Then:
- include Cafe A in primary results
- exclude Gym B entirely from cafe recommendations
- exclude Cafe C from primary results
- optionally mention Cafe C under Saved but not nearby
```

If Cafe A does not exist:

```text
Then:
- do not recommend Gym B
- answer: 你的 SAV-E 裡附近沒有咖啡廳
- offer: Search nearby unsaved cafes
```

Also required:

- If current location permission is missing, ask for location permission or offer `saved cafes anywhere`; do not pretend to know where the user is.
- Source-only clues without coordinates cannot satisfy `nearby`.
- Wrong category cannot satisfy the result even if it is closer.
- LLM output must be validated against the gated candidate IDs. If it references anything outside allowed IDs, drop to deterministic response.

Verification:

```bash
xcodebuild test -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:SAVETests/SaveLocationIntentRecommendationServiceTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' CODE_SIGNING_ALLOWED=NO
/Users/jhinresh/brain/scripts/brain containment check --strict
```

## P1 — Structured intent parser with LLM fallback

### Goal

Make natural language queries understandable without letting the model invent answers.

### Scope

Create deterministic parser first; use model only to fill a strict `SaveSearchIntent` schema when deterministic confidence is low.

### Deterministic parser must cover

```text
附近咖啡廳
附近 cafe
coffee near me
我想喝咖啡
我今天想喝奶茶
晚餐附近有什麼
show saved cafes
saved boba near me
```

### LLM fallback contract

Input to model:

```json
{
  "task": "parse_user_place_query",
  "allowedCategories": ["food", "cafe", "bar", "attraction", "stay", "shopping"],
  "query": "附近咖啡廳"
}
```

Output must be strict JSON only:

```json
{
  "kind": "categoryRecommendation",
  "requiredCategories": ["cafe"],
  "locationMode": { "type": "currentLocation", "radiusMeters": 2000 },
  "sourceScope": "savedFirstAllowPublicFallback",
  "mustMatchCategory": true,
  "mustMatchLocation": true,
  "confidence": 0.94
}
```

Validation rules:

- Reject unknown categories.
- Clamp radius to safe range, e.g. 500m–20km.
- Reject `mustMatchLocation=false` if query contains `nearby`, `near me`, `附近`, `around here`.
- Reject `mustMatchCategory=false` if query contains a known category like cafe/咖啡廳/奶茶.
- If model parse fails, use deterministic fallback or honest unknown intent.

Acceptance criteria:

- `附近咖啡廳` parses to cafe + current location + category/location gates.
- `我今天想喝奶茶` parses to cafe/drink intent; if no location phrase exists, default to saved memory search, not public map search.
- `coffee in LA` parses to cafe + named area, not current location.
- Parser tests pass without any API key.
- API-key/model tests are optional/integration-only and must be skipped in CI if no key is present.

## P2 — Grounded answer + drawer UI

### Goal

Make the answer feel intelligent and trustworthy, not like a raw filter result.

### Scope

Render structured recommendation sections and reasons in the drawer.

Likely files:

```text
Modify: SAV-E/Models/AIResponse.swift
Modify: SAV-E/Views/Drawer/AIDrawerView.swift
Modify: SAV-E/ViewModels/AIDrawerViewModel.swift
Modify: SAV-E/Views/Map/MapView.swift
Test: SAVETests/AIDrawerIntentRecommendationTests.swift
```

Recommended response model extension:

```swift
struct SaveRecommendationSection: Equatable, Codable {
    let id: String
    let title: String
    let subtitle: String?
    let placeIds: [String]
    let reasonByPlaceId: [String: [String]]
}
```

User-facing copy examples:

When results exist:

```text
我找到 2 間你存過、目前附近、符合咖啡廳的地方。
```

Per result:

```text
Kumquat Coffee
0.7 mi away · Cafe · Map Stamp
Why: saved from Instagram; note mentions coffee / pastries
```

When only far saved cafes exist:

```text
你有存過咖啡廳，但不在你目前附近。
最近的在 20km 外。
要不要我找附近沒存過的咖啡廳？
```

When no result exists:

```text
你的 SAV-E 裡附近沒有咖啡廳。
我沒有推薦其他健身房/餐廳，因為你問的是咖啡廳。
```

Map behavior:

- Primary matching saved places -> `MapActionData.filterPins`.
- Best match with high confidence -> optional `focusRegion`.
- Far saved places -> do not auto-focus unless user taps that section.
- Unsaved candidates -> separate marker style and separate section.

Acceptance criteria:

- Results are sectioned.
- Each recommendation explains `why this fits`.
- Empty states are honest and actionable.
- No debug parser text is shown as primary UI.
- No new AI tab.

## P3 — Public nearby fallback, explicitly unsaved

### Goal

If the user's memory has no answer, SAV-E can help find nearby public candidates without confusing them with saved memory.

### Scope

Public map search is only triggered by explicit user action or explicit query wording.

Trigger examples:

```text
Search nearby unsaved cafes
找附近新的咖啡廳
recommend new cafe near me
```

Non-trigger examples:

```text
附近咖啡廳
```

For non-trigger examples, first answer from SAV-E memory and offer fallback.

Likely files:

```text
Modify/Create: SAV-E/Services/MapPlaceSearchService.swift
Modify: SAV-E/Services/SaveSearchController.swift
Modify: SAV-E/ViewModels/MapViewModel.swift
Modify: SAV-E/Views/Map/MapView.swift
Test: SAVETests/SaveNearbyUnsavedCandidateTests.swift
```

Acceptance criteria:

- Public results are labeled `Nearby unsaved candidates`.
- Unsaved results never appear under `From your SAV-E`.
- Tapping an unsaved candidate opens `Save this place`, not a memory card.
- Saving creates a Map Stamp only after explicit user confirmation.
- Public fallback does not run automatically on map load/pan/current-location focus.

## P4 — Model gateway, evaluation harness, and provider decision

### Goal

Use an LLM where it helps, but make provider/model choice evidence-based.

### Why P4 exists

The current bug can happen even with GPT if retrieval is not gated. Model upgrade alone is not a fix.

The old `flash-lite`-first model order was too cheap/weak for polished Ask SAV-E behavior. The current shared default is:

```text
1. gemini-3.5-flash
```

`flash-lite` is acceptable for cheap classification experiments, but it should not be the first model trusted for nuanced multilingual intent + explanation unless outputs are strictly validated.

### Recommended model split

P0/P1 deterministic path:

```text
No model required.
Must pass offline tests.
```

P1 uncertain intent parsing:

```text
Gemini 2.5 Flash is probably enough if:
- JSON schema is strict
- temperature = 0
- output is validated
- bad output falls back to deterministic / unknown intent
```

P2 answer phrasing:

```text
Gemini 2.5 Flash is likely enough for short grounded explanations from allowed candidates.
Do not use the model to choose candidates outside the deterministic allowlist.
```

P3 public discovery summary:

```text
Gemini can summarize why public candidates fit, but map/provider data must supply the candidate identity, category, coordinates, rating, and URL.
```

P4 higher-quality planning / multilingual reasoning:

```text
Consider GPT only for complex planning or ambiguous multilingual queries after the deterministic gates exist.
Good uses: richer explanations, multi-stop tradeoffs, itinerary wording, query disambiguation.
Bad use: direct place recommendation from raw memory blob with no allowed candidate list.
```

### Provider decision

Do **not** switch everything to GPT immediately.

Recommended decision:

```text
Keep Gemini API for now, with `gemini-3.5-flash` as the shared default model.
Use a provider gateway later only if SAV-E needs to compare Gemini vs another provider on the same fixtures.
```

Suggested default after P0/P1:

```text
intent parsing: deterministic first, Gemini 2.5 Flash fallback
candidate retrieval: deterministic only
answer text: Gemini 2.5 Flash from allowed candidates
complex planning: model gateway; evaluate Gemini 2.5 Flash vs GPT before choosing
```

If dogfood still shows wrong intent parsing after P0/P1 validation, then test GPT as the fallback model. But do not pay for GPT to compensate for missing geo/category gates.

### Model evaluation fixture set

Create a small provider-agnostic eval file:

```text
Tests/Fixtures/AskSaveIntentEvalFixtures.json
```

Fixtures:

```json
[
  {
    "query": "附近咖啡廳",
    "expected": {
      "requiredCategories": ["cafe"],
      "locationMode": "currentLocation",
      "mustMatchCategory": true,
      "mustMatchLocation": true
    }
  },
  {
    "query": "我今天想喝奶茶",
    "expected": {
      "requiredCategories": ["cafe"],
      "locationMode": "unspecifiedOrSavedAnywhere",
      "mustMatchCategory": true
    }
  },
  {
    "query": "coffee in LA",
    "expected": {
      "requiredCategories": ["cafe"],
      "locationMode": "namedArea:LA"
    }
  },
  {
    "query": "附近健身房",
    "expected": {
      "supportedCategory": false,
      "shouldNotReturnCafeOrFood": true
    }
  }
]
```

Eval pass criteria:

- Model parse accuracy >= 95% on core fixtures.
- Zero wrong-category recommendations after deterministic gating.
- Zero wrong-location primary recommendations for `nearby` fixtures.
- JSON parse failure rate < 2%.
- Latency acceptable for drawer interaction.
- Cost acceptable for frequent mobile queries.

### Gateway shape

```swift
protocol SaveLLMClient {
    func parseIntent(_ request: IntentParseRequest) async throws -> IntentParseResult
    func renderGroundedAnswer(_ request: GroundedAnswerRequest) async throws -> String
}
```

Implementations:

```text
GeminiSaveLLMClient
OpenAISaveLLMClient // optional, behind config/feature flag
DeterministicSaveIntentParser // always available, no network
```

Do not commit API keys. Keep provider selection in local config/Secrets, not hardcoded production secrets.

## Concrete regression matrix

### Regression 1 — nearby cafe with wrong-category nearby item

Input:

```text
currentLocation: 34.05,-118.25
places:
- Cafe A | cafe | 1km
- Gym B | attraction/shopping/unsupported | 0.3km
- Cafe C | cafe | 20km
query: 附近咖啡廳
```

Expected:

```text
primary: Cafe A
excluded: Gym B
secondary: Cafe C under saved-but-not-nearby
message: found saved nearby cafe(s)
mapAction: filterPins([Cafe A])
```

### Regression 2 — no nearby cafe, wrong-category nearby item exists

Input:

```text
currentLocation: 34.05,-118.25
places:
- Gym B | attraction/shopping/unsupported | 0.3km
- Cafe C | cafe | 20km
query: 附近咖啡廳
```

Expected:

```text
primary: none
excluded: Gym B
secondary: Cafe C under saved-but-not-nearby
message: 你的 SAV-E 裡附近沒有咖啡廳
cta: Search nearby unsaved cafes
mapAction: nil or resetPins
```

### Regression 3 — milk tea without location phrase

Input:

```text
places:
- Boba A | cafe | note mentions boba
- Coffee B | cafe | no boba evidence
- Dinner C | food
query: 我今天想喝奶茶
```

Expected:

```text
primary: Boba A
secondary/low score: Coffee B only if no stronger boba result exists, and reason must say cafe match not boba proof
excluded: Dinner C
location gate: not required unless current-location phrasing appears
```

### Regression 4 — unsupported gym query

Input:

```text
query: 附近健身房
```

Expected:

```text
If gym category is unsupported:
- do not map to cafe/food/attraction by accident
- answer: SAV-E doesn't have a gym category/search mode yet, but can search saved place names/notes or public nearby places if you want
```

## PR breakdown

### PR 1 — P0 hard gates

- Add `SaveSearchIntentParser` deterministic core.
- Add `SaveLocationIntentRecommendationService`.
- Add distance helper tests.
- Wire `AIDrawerViewModel.submit()` to try gated intent recommendation before Gemini.
- Acceptance: wrong-category/wrong-location regressions pass.

### PR 2 — P1 structured parser + LLM fallback

- Add strict intent JSON schema.
- Move Gemini call for intent parsing behind a client method.
- Ensure parser tests do not require API keys.
- Add optional integration test skipped without API key.

### PR 3 — P2 drawer sections and reasons

- Add sectioned response model or extend `SaveSearchResponse`.
- Render `From your SAV-E nearby`, `Saved but not nearby`, `Nearby unsaved candidates`.
- Add reason chips and honest empty states.

### PR 4 — P3 explicit public fallback

- Wire public nearby search only behind explicit action.
- Preserve unsaved candidate state and save confirmation.
- Add map marker separation tests.

### PR 5 — P4 model gateway/eval

- Add provider-agnostic eval fixtures.
- Add `SaveLLMClient` protocol.
- Keep Gemini default but make model order configurable.
- Optionally add OpenAI/GPT client behind feature flag after eval.

## Non-goals

- No full travel-planner rewrite.
- No new AI tab.
- No auto-save of public candidates.
- No fake coordinates.
- No source-only clue as nearby map result.
- No API key commits.
- No broad backend migration unless P3 chooses a server-side public search adapter later.

## Final model answer

Gemini API is probably enough for P1/P2 if the task is framed correctly:

```text
structured intent parse + grounded wording from allowed candidate IDs
```

The old first model, `gemini-2.5-flash-lite`, was too weak/cheap to be the trusted default for nuanced multilingual Ask SAV-E behavior. Use deterministic gates first, then use the shared `gemini-3.5-flash` default for intent fallback and answer polish.

GPT may be worth testing for P4 planning and ambiguous multilingual reasoning, but it should not be used as a band-aid for missing geo/category constraints. The acceptance test is not “sounds smarter”; it is:

```text
zero gyms for cafe queries
zero far places for nearby primary results
honest no-result answer when memory has no match
```
