# SAV-E Intelligent Place Memory: Five-PR Spec

## Goal

Turn SAV-E from a passive saved-place app into an intelligent place-memory agent.

The app should not add a generic AI/chat tab or many permanent tabs. It should make the existing map/search/drawer surfaces state-aware:

```text
messy source / map place / saved memory
→ SAV-E understands the object state
→ drawer explains evidence + uncertainty
→ drawer offers the next best action
→ user saves / recovers / plans / reviews / proves
```

## Product Thesis

A dumb app stores places. An intelligent SAV-E keeps place memory state and knows what to do next.

Core state machine:

```text
Source-only clue
→ Pending candidate
→ Map-visible unsaved place
→ Saved place
→ Trip stop
→ Tried memory
→ Private review
→ Receipt/proof-backed review
```

Each state needs:

- what SAV-E knows
- what SAV-E is missing
- what evidence/source exists
- primary next action
- secondary useful actions
- whether the object is allowed to become a map pin / saved memory / review / trip stop

## Non-Goals Across All Five PRs

Do not turn this into a broad rewrite.

Out of scope unless explicitly called out in a later PR:

- No new generic AI chat tab.
- No tab explosion: avoid adding separate tabs for Search, AI, Nearby, Guides, Reviews, etc.
- No fake coordinates or fake exact places.
- No logged-in social scraping.
- No payment, wallet, chain write, merchant, or receipt API integration.
- No public posting/sharing by default.
- No full social feed.
- No unverified source-only clue promoted to saved place without user confirmation.

## Navigation / UX Principle

Keep persistent surfaces small:

```text
Map/Search
Saves/Memory
Trips
```

Make the drawer the agent surface:

```text
selected object
→ state-aware drawer
→ evidence / missing info / why shown
→ next best actions
```

The drawer should feel like SAV-E is thinking about the current place, not just displaying fields.

---

# PR 1 — Agent Action Drawer v0

## Status

Implemented in PR #147: `feat: add agent action drawer model`.

## Goal

Upgrade the existing result/card drawer from a flat CTA into a state-aware agent action drawer.

## Problem

Before this PR, a place/search result can show a primary action, but the app does not clearly explain:

- what state the object is in
- why this object is being shown
- what evidence exists
- what is missing
- what SAV-E thinks the user should do next

That makes SAV-E feel like a normal app, not an agent.

## Product Behavior

Every searchable place-memory object should expose an `agentDrawer` model:

```swift
SaveSearchResult.agentDrawer
```

The drawer should include:

- `heading`
- `contextLine`
- `evidenceSummary`
- `primaryAction`
- `secondaryActions`
- `missingInfo`

## State → Action Rules

### Source-only clue

```text
State: sourceOnlyClue
Primary: Find exact place
Secondary: Open source
```

Expected drawer copy:

```text
Recover exact place
SAV-E has a source clue but still needs a confirmed map match.
Missing: exact map place / coordinates / address
```

### Pending candidate

```text
State: pendingCandidate
Primary: Save this place / confirm candidate
Secondary: Open source, Find exact place
```

### Map-visible unsaved place

```text
State: mapVisibleUnsavedPlace
Primary: Save this place
Secondary: Plan around this, Open source, Show nearby
```

Important: this is not a saved memory yet.

### Saved place

```text
State: savedPlace
Primary: Plan around this
Secondary: Open source, Add to trip, Show nearby, Mark as tried
```

### Tried memory

```text
State: triedMemory
Primary: Add private review
Secondary: Add proof, Plan around this, Add to trip
```

### Private review

```text
State: review
Primary: Add proof
Secondary: Open source, Plan around this
```

## Files

Existing implementation touches:

- `Wanderly/Models/SaveSearchModels.swift`
- `Wanderly/Views/List/PlaceListView.swift`
- `Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift`

## Acceptance Criteria

- Source-only clues show recovery-first actions.
- Unsaved map places show save-first actions.
- Saved places show plan-first actions.
- Tried/review states show review/proof actions.
- Search result UI shows an agent drawer preview instead of only a flat action label.
- Tests cover at least source-only, saved, and unsaved map states.

## Verification

```bash
xcodebuild test -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' -only-testing:WanderlyTests/SaveSearchControllerTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
~/brain/scripts/brain containment check --strict
```

---

# PR 2 — Evidence Drawer v0

## Goal

Make SAV-E explain what it knows and what it does not know for every place/source.

## Problem

SAV-E cannot feel intelligent if it only says “saved” or “not saved.” It needs to show evidence and uncertainty:

```text
source URL
caption/OCR/source text
creator/provenance
possible venue handles
confidence
missing fields
candidate matches
why this result is shown
```

## Product Behavior

The drawer gets an evidence section below the agent action header.

It should answer:

```text
Where did this come from?
Why does SAV-E think this is a place?
Is the exact map place confirmed?
What is missing?
What should happen next?
```

## Data Model

Add a UI-facing evidence model, separate from raw parser diagnostics:

```swift
struct SaveEvidenceDrawerModel: Hashable {
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var provenanceLabel: String?
    var confidenceLabel: String
    var evidenceAtoms: [SaveEvidenceAtom]
    var missingFields: [String]
    var recoveryQueries: [String]
    var candidateExplanation: String?
}

struct SaveEvidenceAtom: Identifiable, Hashable {
    var id: UUID
    var kind: SaveEvidenceAtomKind
    var label: String
    var value: String
}

enum SaveEvidenceAtomKind: String, Hashable {
    case sourceURL
    case caption
    case creator
    case venueHandle
    case address
    case city
    case coordinates
    case rating
    case reviewCount
    case userNote
    case receipt
}
```

## UI Sections

### Confirmed saved place

```text
Evidence
- Source: Instagram
- Address: 123 Main St
- Coordinates: confirmed
- User state: saved
```

### Source-only clue

```text
Evidence
- Source: Instagram Reel
- Creator/provenance: @creator
- Caption clue: “best pasta in LA”

Missing
- exact venue
- address
- coordinates

Next recovery queries
- instagram reel <id> place
- best pasta LA @creator
```

### Unsaved map place

```text
Evidence
- Source: Apple/Google map result
- Rating: 4.6
- Reviews: 4,100
- Coordinates: present

State
- Not saved to SAV-E yet
```

## Files Likely Touched

- `Wanderly/Models/SaveSearchModels.swift`
- `Wanderly/Services/SaveSearchController.swift`
- `Wanderly/Views/List/PlaceListView.swift`
- Possibly a new file: `Wanderly/Views/List/SaveEvidenceDrawerView.swift`
- Tests: `Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift`

## Acceptance Criteria

- Every `SaveSearchResult` can derive an evidence drawer model.
- Source-only records expose missing fields and recovery queries when present.
- Unsaved map candidates show map evidence without pretending to be SAV-E memory.
- Saved places show source/evidence when present.
- UI visually separates actions from evidence.
- No source-only clue gets promoted to a saved place by this PR.

## Test Cases

Add tests for:

```text
source-only clue with missing exact place
→ evidence drawer includes missing fields + recovery query

unsaved map candidate with rating/review count
→ evidence drawer says map-visible but unsaved

saved place with source URL
→ evidence drawer includes source platform and address
```

## Verification

```bash
xcodebuild test -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' -only-testing:WanderlyTests/SaveSearchControllerTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
~/brain/scripts/brain containment check --strict
```

---

# PR 3 — Save Unsaved Map Place v0

## Goal

Let users tap a map-visible unsaved place and save it into SAV-E.

This is the Roamy-parity behavior the product needs:

```text
map has place
→ user taps place
→ drawer opens
→ Save this place
→ SAV-E memory created
→ place now appears under From your SAV-E
```

## Problem

A map/search result may already contain a real external place with coordinates/rating/reviews, but it is not part of the user’s SAV-E memory. If the user cannot collect it quickly, SAV-E feels like a read-only map overlay.

## Product Behavior

For `mapVisibleUnsavedPlace`:

- primary action: `Save this place`
- save action creates a normal saved place/memory record
- saved result moves from `New recommendations` to `From your SAV-E`
- saved memory preserves source/evidence metadata
- saved memory does not inherit public map reviews as private SAV-E reviews

## State Transition

```text
mapVisibleUnsavedPlace
→ user taps Save this place
→ savedPlace
```

Preserve provenance:

```text
source: map provider / search provider / guide / agent recommendation
external rating/review count: external metadata only
user state: saved
private review: none yet
```

## Data / Persistence

Add a small save command. Possible shape:

```swift
struct SavePlaceDraft: Hashable {
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory?
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var evidence: [String]
    var externalRating: Double?
    var externalReviewCount: Int?
}
```

Controller/service API:

```swift
func makeSaveDraft(from result: SaveSearchResult) -> SavePlaceDraft?
func saveMapCandidate(_ draft: SavePlaceDraft) async throws -> Place
```

If full backend persistence is too large, do this PR as local/store-compatible foundation and explicitly leave backend sync to a follow-up.

## Files Likely Touched

- `Wanderly/Models/SaveSearchModels.swift`
- `Wanderly/Services/SaveSearchController.swift`
- `Wanderly/ViewModels/PlaceListViewModel.swift`
- `Wanderly/Views/List/PlaceListView.swift`
- possibly app storage/local repository files after inspection
- Tests under `Tests/SocialPlacePipelineTests/`

## Acceptance Criteria

- `mapVisibleUnsavedPlace` can produce a valid `SavePlaceDraft`.
- Draft preserves title, address, coordinates, category, source URL/platform, external rating/review count, and evidence.
- Saving transitions the object into saved-place state.
- Saved place appears in `From your SAV-E` on the next search/list refresh.
- External public rating/review count is not written as user review.
- Source-only clues cannot use this path unless they first become a confirmed map candidate.

## Test Cases

```text
unsaved map candidate → makeSaveDraft
expected: draft has coordinates, rating, source, evidence

save draft → search again
expected: result appears in From your SAV-E as savedPlace

source-only clue → makeSaveDraft
expected: nil / blocked because exact place is missing
```

## Manual UI Verification

1. Open map/search with an unsaved candidate.
2. Tap candidate.
3. Confirm drawer says `Map place · Unsaved`.
4. Tap `Save this place`.
5. Search/list refreshes.
6. Confirm the place is now under `From your SAV-E`.
7. Confirm drawer primary action changes to `Plan around this`.

---

# PR 4 — Plan Around This v0

## Goal

Make SAV-E plan around the user’s saved places instead of generating generic travel itineraries.

## Product Difference

Do not build:

```text
Plan a 3-day trip to Tokyo from scratch
```

Build:

```text
Plan around this saved place / these saved places
```

SAV-E should use the user’s place memory first, then fill gaps with nearby useful additions.

## Product Behavior

From a saved place or unsaved map candidate drawer:

```text
Plan around this
```

Generates a plan shell:

```text
Anchor
- selected place

Nearby from your SAV-E
- saved/pending/tried places nearby

New suggestions
- nearby things that fill gaps: coffee, dessert, museum, shop, viewpoint

Route shell
- suggested stop order
- saved vs new labels
- why each new stop was added
```

## Data Model

Add local planning model:

```swift
struct SavePlanAroundRequest: Hashable {
    var anchorResultID: UUID
    var anchorTitle: String
    var latitude: Double?
    var longitude: Double?
    var cityOrArea: String?
    var duration: SavePlanDuration
    var intent: SavePlanIntent
}

enum SavePlanDuration: String, Hashable {
    case oneHour
    case halfDay
    case fullDay
}

enum SavePlanIntent: String, Hashable {
    case foodAndNearbyThings
    case coffeeWalk
    case dateNight
    case shoppingAndFood
    case custom
}

struct SavePlanAroundDraft: Hashable {
    var anchor: SavePlanStop
    var nearbySaved: [SavePlanStop]
    var newSuggestions: [SavePlanStop]
    var routeNotes: [String]
    var explanation: String
}

struct SavePlanStop: Identifiable, Hashable {
    var id: UUID
    var title: String
    var source: SavePlanStopSource
    var category: PlaceCategory?
    var distanceLabel: String?
    var reason: String
}

enum SavePlanStopSource: String, Hashable {
    case userSaved
    case pendingCandidate
    case unsavedMapCandidate
    case newRecommendation
    case guideStop
}
```

## Ranking Rules

Use this priority order:

1. User saved places near the anchor.
2. Pending candidates with enough evidence.
3. Places from copied/saved guides.
4. Unsaved map candidates near the anchor.
5. New map/web recommendations.

## Files Likely Touched

- `Wanderly/Models/SaveSearchModels.swift`
- New: `Wanderly/Models/SavePlanAroundModels.swift`
- New: `Wanderly/Services/SavePlanAroundController.swift`
- `Wanderly/Views/List/PlaceListView.swift` or drawer view
- Tests: new `Tests/SocialPlacePipelineTests/SavePlanAroundControllerTests.swift`

## Acceptance Criteria

- Saved place drawer exposes `Plan around this`.
- Planning controller can create a deterministic local plan shell from known nearby data.
- Plan labels every stop as `From your SAV-E` or `New suggestion`.
- Plan explanation says why new stops were added.
- If anchor has no coordinates, plan is blocked with a useful missing-info message.
- No generic AI itinerary generation required in this PR.

## Test Cases

```text
saved anchor + nearby saved coffee + unsaved museum
→ plan draft includes anchor, nearby saved, new suggestion, explanation

anchor without coordinates/city
→ blocked plan with missing location info

food-heavy saved cluster
→ plan shell suggests non-food gap fillers when provided as candidates
```

## Manual UI Verification

1. Open saved restaurant drawer.
2. Tap `Plan around this`.
3. Confirm plan shell uses selected restaurant as anchor.
4. Confirm nearby saved places are labeled separately from new suggestions.
5. Confirm generated text explains why each new suggestion was added.

---

# PR 5 — Guide Customization v0

## Goal

Turn guides into copyable/customizable itinerary templates that use the user’s saved places.

Do not start with a full social feed. Start with the agent behavior:

```text
creator/public/shared guide
+ my saved places
+ constraints
→ customized trip draft
```

## Product Behavior

User opens a guide:

```text
3 Days in Tokyo Food Guide
```

SAV-E says:

```text
You already saved 5 places near this guide.
Customize it with your saved places?
```

Actions:

- Save guide.
- Copy to my trips.
- Add guide stops to SAV-E.
- Customize with my saved places.

## Data Model

```swift
struct SaveGuide: Identifiable, Hashable {
    var id: UUID
    var title: String
    var sourceURL: String?
    var sourcePlatform: SourcePlatform?
    var creatorLabel: String?
    var cityOrArea: String?
    var stops: [SaveGuideStop]
    var evidence: [String]
}

struct SaveGuideStop: Identifiable, Hashable {
    var id: UUID
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: PlaceCategory?
    var sourceURL: String?
    var state: SaveGuideStopState
}

enum SaveGuideStopState: String, Hashable {
    case guideOnly
    case alreadySaved
    case copiedToTrip
    case savedToMemory
    case needsRecovery
}

struct SaveGuideCustomizationDraft: Hashable {
    var originalGuide: SaveGuide
    var keepStops: [SaveGuideStop]
    var swapInSavedPlaces: [SavePlanStop]
    var addNearbySuggestions: [SavePlanStop]
    var explanation: String
}
```

## Customization Rules

- Preserve original guide attribution/source.
- Never claim guide stops are user-saved unless user explicitly saves/copies them.
- Match user saved places by city/area/category/proximity when coordinates exist.
- Mark uncertain guide stops as `needsRecovery`, not fake map places.
- Output a draft trip, not a public post.

## Files Likely Touched

- New: `Wanderly/Models/SaveGuideModels.swift`
- New: `Wanderly/Services/SaveGuideCustomizationController.swift`
- Possible UI shell under `Wanderly/Views/Trips/` or drawer integration
- Tests: new `Tests/SocialPlacePipelineTests/SaveGuideCustomizationControllerTests.swift`
- Spec references: `specs/agent-map-trip-planner-v0.md`

## Acceptance Criteria

- A guide can be represented as structured stops with source attribution.
- Guide stops can be classified as guide-only, already-saved, copied-to-trip, saved-to-memory, or needs-recovery.
- Customization draft can keep original guide stops, swap in user saved places, and add nearby suggestions.
- The draft preserves saved vs guide-only vs new labels.
- No public guide feed, comments, follows, or publishing in this PR.

## Test Cases

```text
public guide with 3 stops + user has 2 nearby saved places
→ customization draft keeps guide stops and suggests saved swaps

uncertain guide stop without address/coordinates
→ state is needsRecovery

copy guide to trip
→ copied stops are trip draft stops, not auto-saved memories unless explicitly saved
```

## Manual UI Verification

1. Open a guide fixture/shell.
2. Confirm source/creator attribution is visible.
3. Tap `Customize with my saved places`.
4. Confirm SAV-E shows kept guide stops and suggested saved swaps.
5. Confirm no guide stop is silently added to saved memory without user action.

---

# Suggested PR Order

```text
PR 1 Agent Action Drawer v0       ✅ done / #147
PR 2 Evidence Drawer v0           next
PR 3 Save Unsaved Map Place v0    after evidence is visible
PR 4 Plan Around This v0          after saved/unsaved transitions exist
PR 5 Guide Customization v0       after plan model exists
```

Reasoning:

- PR 1 gives every object a state-aware action surface.
- PR 2 makes the drawer trustworthy by showing evidence and uncertainty.
- PR 3 lets map-visible places become actual SAV-E memory.
- PR 4 uses SAV-E memory as trip-planning anchors.
- PR 5 uses trips/plans to personalize guides.

# Cross-PR Definition of Done

Every PR must include:

- XCTest coverage for the new state/action behavior.
- No fake precision: source-only stays source-only until recovered/confirmed.
- UI copy that distinguishes saved memory, unsaved map place, source clue, trip stop, tried memory, and private review.
- Build passes on iOS simulator.
- Containment check passes before PR.

Required commands:

```bash
xcodebuild test -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' -only-testing:WanderlyTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=WanderlyConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
~/brain/scripts/brain containment check --strict
```

# Product Copy Guardrail

Use clear labels over cute ambiguity.

Good:

```text
Map place · Unsaved
Source clue · Needs exact place
Saved from Instagram
Tried · Private memory
Review · Proof optional
```

Bad:

```text
Maybe saved
AI found this
Popular place
Verified
Receipt-backed
```

Do not use `verified` unless proof status actually supports it.

# Future Follow-Ups After These Five PRs

Only after the five-PR foundation is in place:

- real map provider search integration
- location-aware nearby notifications
- AI route optimization
- receipt/proof ingestion
- public/shareable guide cards
- taste graph ranking
- source/creator quality scoring
