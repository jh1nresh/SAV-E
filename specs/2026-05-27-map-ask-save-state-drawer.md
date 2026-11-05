# SAV-E Map + Ask/Save Bar + State-Aware Drawer Spec

> Status: PM/spec-only implementation handoff
> Date: 2026-05-27
> Owner: JhiNResH
> Source: product direction from SAV-E simplification discussion — keep the app Apple Maps-simple while hiding agent complexity behind state-aware place memory
> Related specs: `specs/2026-05-26-memory-first-command-drawer.md`, `specs/2026-05-26-ask-save-location-intent-agent.md`, `specs/2026-05-25-save-map-search-intent-recommendations.md`, `specs/2026-05-26-adaptive-glass-map-drawer.md`

## Blunt product call

SAV-E should not add more visible feature surfaces right now. The app is at risk of looking like several products at once:

```text
map
+ saved places
+ unsaved candidates
+ review candidates
+ social parser
+ Google Maps importer
+ lists
+ AI chat
+ future Roomy/action/SLL-R ideas
```

The product should collapse back to one simple loop:

```text
Map + Ask/Save bar + state-aware place drawer
```

The complexity should live inside four place-memory states, not in tabs or feature panels:

```text
Clue
→ Review Candidate
→ Map Stamp
→ Action / Receipt
```

This is the trust line:

```text
Apple Maps-like simplicity on the surface.
SAV-E evidence + private memory + bounded LLM reasoning underneath.
```

## Goal

Make SAV-E feel like a clean place-memory map, not a general AI travel/workflow app:

```text
Save messy place signals
→ ask private place memory
→ act through the selected place drawer
```

The main screen should communicate three user verbs only:

```text
Save
Ask
Act
```

## Product principle

```text
LLM = front-desk reasoning layer
Vault = source of truth
MapKit / Places = map truth
State machine = memory trust contract
Drawer = agent action surface
User confirmation = gate for risky writes/actions
```

Do **not** build this as a new AI tab, marketplace tab, trip-planning tab, or commerce/voucher tab.

## Target UX

### Main surface

```text
Full-screen map
+ compact identity / profile controls
+ current-location control
+ bottom Ask/Save bar
+ bottom place drawer when a place/result is selected
```

The top of the map should stay quiet. Category filters, import actions, source review, and planning prompts should live in the drawer / Ask/Save flow.

### Ask/Save bar

Placeholder options:

```text
Ask SAV-E or paste a place…
```

or shorter:

```text
Ask or save a place…
```

The bar routes user input into one of five modes:

```text
memory_query     -> ask saved/private place memory
map_search       -> find explicit place/category/nearby candidates
import_parse     -> parse Google Maps / IG / TikTok / X / screenshot source
trip_plan        -> plan from confirmed memories first
place_action     -> draft or start an action for a selected place
```

The user should not need to know these route names.

### State-aware drawer

The selected place drawer is the agent surface. It should derive the primary action from the place state:

```text
Clue              -> Find exact place
Review Candidate  -> Confirm / Save candidate
Map-visible unsaved candidate -> Save this place
Map Stamp          -> Plan around this
Tried memory       -> Add private review
Action / Receipt   -> View receipt / Add review / Use again
```

Every drawer should answer:

```text
What is this?
Why is SAV-E showing it?
Can I trust it as a saved memory yet?
What is the one best next action?
```

## Four-state memory model

### 1. Clue

Meaning:

```text
SAV-E found a place-like signal but cannot verify the exact place yet.
```

Examples:

- IG Reel caption says “best brunch in Irvine” but no venue name.
- TikTok has food/category/city clues but no address.
- X post mentions a cafe vibe without reliable coordinates.
- Google Maps list item failed exact match.

UI language:

```text
Clue
Source clue
Needs exact place
```

Primary action:

```text
Find exact place
```

Rules:

- No fake coordinates.
- No navigation.
- No Map Stamp styling.
- Can appear in Review Nest / drawer list but should not become a primary map pin unless coordinates are verified.

### 2. Review Candidate

Meaning:

```text
SAV-E has a likely place candidate, but user or evidence confirmation is still needed.
```

Examples:

- Tagged venue handle plus city/category.
- MapKit/Google returned a possible match but confidence is not high enough.
- Imported list item has enough title/address to review.

UI language:

```text
Review Candidate
Check before saving
Likely match
```

Primary action:

```text
Confirm place
```

Secondary actions:

```text
Reject
Edit details
View source
```

Rules:

- Must not look identical to confirmed saved Map Stamps.
- If coordinates are reliable, can show a candidate marker, but label it unconfirmed.
- LLM may explain evidence/missing info, but cannot confirm by itself.

### 3. Map Stamp

Meaning:

```text
A user-confirmed saved place memory with stable title/category/coordinates/source context.
```

Examples:

- User saved from Apple Maps / MapKit search.
- User confirmed an import candidate.
- User saved a Google Maps shared place.

UI language:

```text
Map Stamp
Saved memory
From your SAV-E
```

Primary action:

```text
Plan around this
```

Secondary actions:

```text
Directions
Share
Add note
Add to list
Mark tried
```

Rules:

- This is the only normal state that should feel like “trusted saved place.”
- Saved pins should be visually distinctive as SAV-E objects.
- Delete/destructive actions should be behind More, not in the primary row.

### 4. Action / Receipt

Meaning:

```text
Something happened, or is ready to happen, with this place.
```

Examples:

- Reservation draft.
- Message to merchant drafted.
- Claimed receipt.
- Tried place with private review.
- Future SLL-R voucher / redeemable entitlement.

UI language:

```text
Action
Tried
Receipt
Proof
```

Primary action examples:

```text
Add private review
View receipt
Use again
Continue action
```

Rules:

- v0 should only model the state and drawer placement.
- Do not build voucher/payment/merchant execution in this PR.
- Sending, buying, reserving, claiming, or sharing externally requires explicit user confirmation.

## Ask/Save bar routing contract

### Memory query

Input examples:

```text
我之前存過那家 brunch 是哪家？
Irvine cafe I saved
適合約會的餐廳
```

Behavior:

```text
Search confirmed Map Stamps first
→ include Review Candidates only in a clearly labeled section
→ LLM summarizes from retrieved results only
```

### Map search

Input examples:

```text
附近咖啡廳
我今天想喝奶茶
Standard Bread
```

Behavior:

```text
Parse intent/category/location
→ deterministic geo/category gates
→ saved Map Stamps first
→ optional unsaved candidates only when explicitly allowed/labeled
```

No-result behavior:

```text
“I don’t have a saved nearby cafe that matches. Want me to search nearby unsaved candidates?”
```

### Import parse

Input examples:

```text
Google Maps shared list URL
Instagram Reel URL
TikTok URL
X URL
screenshot / pasted text
```

Behavior:

```text
Source capture
→ clue extraction
→ evidence atoms
→ candidate grouping
→ state decision: Clue / Review Candidate / Map Stamp
```

Direct save is allowed only when evidence is strong enough or user confirms.

### Trip plan

Input examples:

```text
幫我排 Irvine 半日
Plan around this place
```

Behavior:

```text
Use confirmed Map Stamps first
→ optionally ask before using public/unsaved candidates
→ output itinerary with source/state labels
```

### Place action

Input examples:

```text
幫我問今晚 7 點兩人有沒有位
幫我分享這家給朋友
幫我記我去過了
```

Behavior:

```text
LLM drafts
→ user confirms
→ system executes or records
→ receipt/action state updates
```

v0 should only support safe local actions and drafts unless an existing action path is already wired.

## Visual direction

### Borrow from Apple Maps

Use:

- clean full-screen map;
- minimal chrome;
- native-feeling selected POI affordance;
- glassy bottom drawer/capsule;
- one clear selected object at a time;
- direct, short labels.

Do **not** copy:

- generic public POI dominance;
- every public place appearing as an equal SAV-E object;
- dense category chips over the map;
- raw debug/evidence text in the main card.

### SAV-E-specific layer

Use state language to make trust visible:

```text
Clue          = faint / source-like / needs work
Review        = candidate / inspection state
Map Stamp     = saved / trusted / stamp-like
Action/Receipt = proof / tried / continuation state
```

Every visually primary SAV-E marker must be tappable and open a drawer.

Default Apple/MapKit POIs are background context. SAV-E objects are the interactive memory layer.

## Existing code context

Likely relevant files:

```text
SAV-E/Legacy/Views/Map/MapView.swift
SAV-E/Legacy/Views/Drawer/AIDrawerView.swift
SAV-E/ViewModels/AIDrawerViewModel.swift
SAV-E/Services/SaveSearchController.swift
SAV-E/Services/SaveAIService.swift
SAV-E/Models/SaveSearchModels.swift
SAV-E/Models/Place.swift
SAV-E/Models/AIResponse.swift
Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift
```

Recent related PRs changed:

```text
PR #217: unsaved POI selection detail / Apple Maps-like selected candidate polish
```

Do not assume branch state is clean before implementation. Inspect `git status --short --branch` first; current local work may be on another UI branch.

## Non-goals

Do not include in this spec’s first implementation PR:

- new AI tab;
- new bottom navigation;
- full trip-planner expansion;
- Roomy marketplace/action layer;
- SLL-R voucher/payment/merchant execution;
- new backend schema;
- TestFlight build bump;
- Google Maps list parser rewrite;
- social parser rewrite;
- public posting/sharing automation;
- merge/deploy/publish.

## P0 implementation slice

### P0 goal

Make the main app shape clear without rebuilding the whole product:

```text
Ask/Save bar routes intent
+ selected drawer shows correct state and one primary action
+ Clue / Review Candidate / Map Stamp / Action labels are consistent
```

### P0 tasks

#### Task 1 — Define state/display model

Create or extend a lightweight display model, preferably not directly hard-coded in SwiftUI views:

```swift
enum SavePlaceMemoryState: Equatable {
    case clue
    case reviewCandidate
    case unsavedMapCandidate
    case mapStamp
    case actionReceipt
}

struct SavePlaceDrawerPresentation: Equatable {
    var state: SavePlaceMemoryState
    var eyebrow: String
    var title: String
    var contextLine: String
    var trustLine: String
    var primaryActionTitle: String
    var primaryActionSystemImage: String
    var secondaryActionTitles: [String]
}
```

Likely files:

```text
Create or modify: SAV-E/Models/SavePlaceDrawerPresentation.swift
Modify: SAV-E/Legacy/Views/Drawer/AIDrawerView.swift
Test: SAVETests/SavePlaceDrawerPresentationTests.swift
```

#### Task 2 — Normalize drawer copy by state

Current/older copy to replace or avoid:

```text
UNSAVED CANDIDATE
MEMORY CARD
not saved
raw evidence paragraphs as primary body
```

Desired copy:

```text
Clue · Needs exact place
Review Candidate · Check before saving
Map Stamp · From your SAV-E
Action / Receipt · Proof attached
Not saved yet
Map search · review before saving
```

Rules:

- `Map Stamp` only for confirmed saved places.
- `Not saved yet` for unsaved map candidates.
- `Review Candidate` for likely but unconfirmed imported/social candidates.
- Evidence should appear as compact chips or secondary explanation, not raw debug body.

#### Task 3 — Turn Ask/Search input into Ask/Save bar copy

Keep existing search behavior, but adjust the product framing:

```text
placeholder: Ask SAV-E or paste a place…
submit button: Ask / Save based on detected input type if trivial, otherwise neutral arrow
```

If implementation detects paste/import URL, the UI may show:

```text
Save from link
```

If implementation detects query language, the UI may show:

```text
Ask SAV-E
```

Do not add a new tab.

#### Task 4 — Drawer primary action per state

Ensure each selected item exposes one visually primary action:

```text
Clue -> Find exact place
Review Candidate -> Confirm place
Unsaved map candidate -> Save this place
Map Stamp -> Plan around this
Action / Receipt -> Add private review / View receipt
```

Secondary actions should be lower hierarchy:

```text
Directions
Share
View source
Add to list
More
```

Destructive actions move into More.

#### Task 5 — Keep LLM bounded

For any Ask/Save response copy, the LLM may summarize only retrieved/verified candidates.

Implementation should preserve this contract:

```text
LLM parses and explains.
Deterministic search retrieves and gates.
User confirms risky writes/actions.
System commits state.
```

Do not let the LLM directly create confirmed Map Stamps, coordinates, receipts, or external actions.

## Acceptance criteria

### Product acceptance

- Main app can be explained as `Map + Ask/Save bar + state-aware drawer`.
- User-facing visible states are limited to `Clue`, `Review Candidate`, `Map Stamp`, and `Action / Receipt` plus `Not saved yet` for map-visible unsaved candidates.
- Selected drawer always has exactly one clear primary action.
- Unsaved or unconfirmed objects never look like confirmed Map Stamps.
- The app does not add a new AI tab or feature-heavy surface.
- Public/unsaved candidates stay labeled and separate from saved memory.
- LLM responses are grounded in retrieved candidates and do not invent place truth.

### UI acceptance

Capture screenshots for:

1. Empty/default map with Ask/Save bar.
2. Ask/Save bar with text query.
3. Unsaved map candidate selected.
4. Review Candidate selected.
5. Saved Map Stamp selected.
6. No-result nearby/category query empty state.

Each screenshot should show:

```text
state label
primary action
source/trust context
no raw debug text dominating the UI
```

### Safety acceptance

- No backend schema change.
- No TestFlight build bump.
- No external send/share/post/payment action.
- No automatic conversion from Clue/Review Candidate into Map Stamp without user confirmation or verified evidence path.

## Verification commands

Run at minimum:

```bash
git status --short --branch
git diff --check
xcodebuild test -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO -only-testing:SocialPlacePipelineTests/SaveSearchControllerTests
xcodebuild build -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
/Users/jhinresh/brain/scripts/brain containment check --strict
```

If `SAVEConfirm` is unavailable, use an available iOS simulator from `xcodebuild -showdestinations -project SAV-E.xcodeproj -scheme SAV-E` and record the substitute destination in the PR body.

## PR breakdown

### PR 1 — State model + drawer copy

Scope:

```text
SavePlaceDrawerPresentation
state labels
primary-action mapping
existing drawer uses model
unit tests for state/action mapping
```

No map behavior changes beyond drawer rendering.

### PR 2 — Ask/Save bar framing

Scope:

```text
placeholder/copy update
route display between ask vs save-like input
no new tab
existing search/import paths reused
```

### PR 3 — Visual pass for markers/cards

Scope:

```text
Map Stamp marker refinement
Review Candidate marker refinement
Clue/review list visual hierarchy
compact evidence chips
remove debug-looking primary text
```

### PR 4 — Bounded LLM answer polish

Scope:

```text
saved-memory-first answer sections
no-result honest copy
separate unsaved/public candidates
LLM response limited to retrieved candidates
```

Do not bundle all four PRs unless the diff is still small and easy to review.

## Open decisions

- Should `Action / Receipt` appear in v0 UI if receipts are not fully implemented, or should v0 label tried/proof states only when data exists?
- Should the Ask/Save bar placeholder say `Ask SAV-E or paste a place…` or `Ask or save a place…`?
- Should `Review Candidate` live in the same selected drawer as Map Stamps or use a slightly more inspection-like Review Nest sheet?

Default recommendation:

```text
Use “Ask SAV-E or paste a place…” for v0.
Do not surface Action / Receipt unless an actual receipt/tried/action record exists.
Keep Review Candidate in the same drawer shell, but with unconfirmed styling and Confirm primary action.
```
