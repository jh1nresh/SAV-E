# SAV-E Interactive First-Run UI Optimization Spec

> Status: Proposed next optimization
> Date: 2026-05-25
> Owner: JhiNResH
> Source: https://x.com/clear_graphics/status/2058988643868725492?s=20
> Related analysis: `/Users/jhinresh/brain/qa/2026-05-25-x-article-agent-product-analysis.md`
> Related specs: `specs/intelligent-save-five-pr-roadmap.md`, `specs/save-agent-product-boundary-v1.md`, `specs/agent-native-save-cards-v0.md`

## Goal

Optimize the current SAV-E product interface around one clear transformation:

```text
messy place signal
→ evidence-backed place memory state
→ next useful action
```

SAV-E should not introduce a broad feature-tab hero, generic AI chat, or a static onboarding carousel. The next UI optimization should make the first session feel like an interactive micro demo of the actual product loop.

## Blunt Product Decision

Do not sell SAV-E as breadth:

```text
Save places. Search. Map. Trips. Reviews.
```

Sell SAV-E as transformation:

```text
Drop a messy place link. SAV-E turns it into an evidence-backed memory and tells you what to do next.
```

This spec is UI/product-only. It should reuse existing parser/review/drawer mechanics and avoid backend or auth changes.

## Current Repo Evidence

Current relevant surfaces:

- `SAV-E/Views/Onboarding/OnboardingView.swift`
  - currently a three-page static carousel:
    - “Save spots while you scroll”
    - “No more fake pins”
    - “Turn memories into trips”
  - good thesis, but it explains instead of demonstrating.
- `SAV-E/Legacy/App/ContentView.swift`
  - always presents `AIDrawerView` over `MapView`.
  - existing drawer can be the agent surface; do not add another permanent tab.
- `SAV-E/Views/List/PlaceListView.swift`
  - already has Agent Action Drawer preview from PR #147.
- `SAV-E/Models/SaveSearchModels.swift`
  - already has state-aware `agentDrawer` modeling.
- `SAV-E/Views/Shared/MemoMascotMark.swift`
  - mascot exists and can guide, but should clarify state/evidence rather than become decorative.
- `SAV-E/Legacy/Views/Shared/EmptyStateView.swift`
  - reusable but currently generic.

## Product Metaphor / State Machine

Use states as the product vocabulary, not feature tabs:

```text
Clue
→ Review Candidate
→ Map Stamp
→ Trip Anchor
→ Trip Plan
```

User-facing meanings:

- **Clue**: SAV-E found a source but does not know the exact place yet.
- **Review Candidate**: SAV-E found a possible place, but needs confirmation.
- **Map Stamp**: confirmed saved place with usable map identity.
- **Trip Anchor**: a saved place selected as the center of planning.
- **Trip Plan**: a lightweight plan around saved places, not a generic itinerary.

Do not use a marketing feature switcher like:

```text
[Save Links] [Map] [Trips] [Reviews]
```

If a switcher pattern is needed, make it a state progression:

```text
[Clue] [Candidate] [Map Stamp] [Trip Plan]
```

## Desired First-Run Experience

### New first-run loop

Replace the static onboarding end-state with an interactive demo shell:

```text
Paste or share a place link
→ SAV-E shows “Clue found”
→ evidence/missing info appears
→ user chooses Find exact place or Save once confirmed
→ app lands in the normal drawer/map surface with the same state language
```

### MVP implementation mode

This does not need real URL parsing inside onboarding if that risks a large change. V0 can use a safe simulated micro demo plus a real CTA into the existing import/share flow.

Acceptable V0 behavior:

```text
Onboarding demo uses a sample messy link card.
CTA opens the app with drawer focused on “Paste your first place link” / import URL affordance.
```

Preferred V1 behavior:

```text
Onboarding accepts a pasted URL and calls existing importURLAsReviewCandidates path.
```

## Current vs Desired Copy

### Onboarding page 1

Current:

```text
Save spots while you scroll
Share an IG post, map link, screenshot, or note. Memo helps SAV-E turn messy clues into reviewable places.
```

Desired:

```text
Drop a messy place link
SAV-E reads the source, shows what it knows, and keeps uncertain places in Review.
```

### Onboarding page 2

Current:

```text
No more fake pins
If SAV-E is unsure, it keeps the clue in Review until you confirm it.
```

Desired:

```text
Clue → Candidate → Map Stamp
Memo shows evidence and missing info before anything becomes a saved place.
```

### Onboarding page 3

Current:

```text
Turn memories into trips
Your confirmed spots become a private travel memory SAV-E can plan from.
```

Desired:

```text
Plan around your saved places
Your Map Stamps become trip anchors — not generic AI itinerary filler.
```

### Primary CTA

Current:

```text
Start with SAV-E
```

Desired:

```text
Paste your first place
```

Fallback if paste entry is not implemented yet:

```text
See how SAV-E works
```

## UI Components to Add / Modify

### 1. FirstRunPlaceDemo model

Create a small view-local model for the demo states.

Suggested file:

```text
SAV-E/Views/Onboarding/OnboardingView.swift
```

or, if it grows:

```text
SAV-E/Views/Onboarding/FirstRunPlaceDemoView.swift
```

Suggested Swift shape:

```swift
private enum FirstRunDemoState: Int, CaseIterable {
    case clue
    case candidate
    case mapStamp
    case tripPlan

    var title: String { ... }
    var subtitle: String { ... }
    var primaryAction: String { ... }
}
```

### 2. FirstRunPlaceDemoView

Show the transformation in one card:

```text
Input
instagram.com/reel/...

SAV-E found a clue
Source: Instagram Reel
Known: pasta, Silver Lake, creator said dinner spot
Missing: exact map place

Next: Find exact place
```

State examples:

#### Clue

```text
Found a place clue
Source: Instagram Reel
Known: food + neighborhood hint
Missing: exact map place
Primary action: Find exact place
```

#### Candidate

```text
Possible match
Candidate: Speranza
Evidence: source text + map name + neighborhood
Missing: user confirmation
Primary action: Confirm candidate
```

#### Map Stamp

```text
Saved as Map Stamp
Place: Speranza · Silver Lake
Evidence: map confirmed
Primary action: Plan around this
```

#### Trip Plan

```text
Trip shell ready
Anchor: Speranza
Nearby saved: 2
New suggestions: 3
Primary action: Review plan
```

### 3. State Progression Chips

Use chips for state progression, not feature breadth:

```text
Clue → Candidate → Map Stamp → Trip Plan
```

The selected chip should control the demo card. Keep this on one screen if possible.

### 4. Paste CTA Surface

After onboarding completion, the first empty app surface should invite the user to paste/share a place signal.

Candidate surfaces:

- `SAV-E/Views/Onboarding/OnboardingView.swift`
- `SAV-E/Legacy/Views/Drawer/AIDrawerView.swift`
- `SAV-E/Legacy/Views/Shared/EmptyStateView.swift`

Desired empty-state copy:

```text
Paste your first place
Drop an Instagram, TikTok, Google Maps, Apple Maps, blog, or note. SAV-E will show evidence before saving anything.
```

Primary action:

```text
Paste link
```

Secondary hint:

```text
You can also share to SAV-E from other apps.
```

## Non-Goals

Do not change these in this optimization:

- No new tab bar item.
- No generic AI chat tab.
- No logged-in Instagram/TikTok scraping.
- No fake coordinates.
- No source-only clue promoted directly to saved place.
- No backend schema migration.
- No auth/account changes.
- No payments, receipts, merchant integrations, or wallet flows.
- No App Store metadata or TestFlight configuration.
- No hard paywall.

## Implementation Plan

### PR 1 — Interactive onboarding demo shell

Goal: replace static explanation with a one-screen micro demo while preserving onboarding completion behavior.

Files:

- Modify: `SAV-E/Views/Onboarding/OnboardingView.swift`
- Optional create: `SAV-E/Views/Onboarding/FirstRunPlaceDemoView.swift`
- Test/snapshot if available: onboarding preview or existing UI tests

Tasks:

1. Add `FirstRunDemoState` and demo copy.
2. Add progression chips: Clue, Candidate, Map Stamp, Trip Plan.
3. Add a demo evidence card that changes with selected state.
4. Replace final CTA copy with `Paste your first place`.
5. Keep `onComplete()` behavior unchanged.
6. Add previews for light/dark or at least standard preview.

Acceptance criteria:

- User can understand the SAV-E loop in one screen without reading a feature carousel.
- The demo shows evidence and missing info.
- The UI never says SAV-E saved an exact place before confirmation.
- Build passes.

### PR 2 — First empty-state CTA alignment

Goal: align post-onboarding empty state with the same transformation loop.

Files to inspect before editing:

- `SAV-E/Legacy/Views/Drawer/AIDrawerView.swift`
- `SAV-E/Legacy/Views/Shared/EmptyStateView.swift`
- `SAV-E/ViewModels/AIDrawerViewModel.swift`
- `SAV-E/ViewModels/MapViewModel.swift`

Tasks:

1. Find the empty state shown when there are no places/review candidates.
2. Change title/copy to `Paste your first place`.
3. Point primary action to the existing URL import affordance if available.
4. Add a secondary share-sheet hint.
5. Do not add a new parser path.

Acceptance criteria:

- Fresh user sees a concrete action, not an empty map/list.
- Copy says evidence appears before saving.
- Action uses existing import/share route.

### PR 3 — Drawer micro-demo alignment

Goal: make the in-app drawer use the same state language as onboarding.

Files:

- `SAV-E/Models/SaveSearchModels.swift`
- `SAV-E/Views/List/PlaceListView.swift`
- `SAV-E/Legacy/Views/Shared/SaveMemoryBadge.swift`

Tasks:

1. Ensure source-only results label as `Clue` or `Source Clue`.
2. Ensure pending candidates label as `Review Candidate`.
3. Ensure confirmed saved places label as `Map Stamp`.
4. Ensure plan-oriented action copy says `Plan around this`.
5. Keep existing Agent Action Drawer actions from PR #147.

Acceptance criteria:

- Onboarding vocabulary matches card/drawer vocabulary.
- Saved places are not visually confused with source-only clues.
- No state loses evidence/missing-info clarity.

## Manual UI Verification

Run the app on the existing simulator target and verify:

```bash
xcodebuild build -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
```

Manual checks:

1. Launch fresh onboarding state.
2. Confirm first screen shows the transformation, not only a feature explanation.
3. Tap each state chip:
   - Clue
   - Candidate
   - Map Stamp
   - Trip Plan
4. Confirm each state shows:
   - source/evidence
   - missing info or confirmation state
   - next best action
5. Tap final CTA.
6. Confirm the app lands in the normal map/drawer surface.
7. Confirm no new permanent tab is added.
8. Confirm source-only language never implies an exact saved place.

## Screenshot Evidence Required for PR

Attach screenshots or simulator captures for:

- Onboarding interactive demo, Clue state.
- Onboarding interactive demo, Candidate state.
- Onboarding interactive demo, Map Stamp state.
- Post-onboarding empty state / first import CTA.
- Existing agent drawer with a source-only result if available.

## Verification Commands

Minimum:

```bash
xcodebuild build -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEConfirm,OS=26.5' CODE_SIGNING_ALLOWED=NO
~/brain/scripts/brain containment check --strict
```

If tests touch `SaveSearchModels` or drawer actions:

```bash
xcodebuild test -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,name=SAVEConfirm,OS=26.5' -only-testing:SAVETests/SaveSearchControllerTests CODE_SIGNING_ALLOWED=NO
```

## Product Risks

- If the demo is too fake, it will feel like marketing instead of product. Keep it visibly tied to current state machine and existing import behavior.
- If the mascot becomes decorative, it will weaken trust. Memo should clarify uncertainty and next action.
- If the CTA promises real parsing before the flow exists, user trust drops. Use simulated demo copy until actual paste/import is wired.
- If the team adds tabs for each capability, SAV-E becomes a normal travel app. Keep the drawer as the agent surface.

## Success Definition

A new user should understand SAV-E in under 15 seconds:

```text
I can drop a messy place signal.
SAV-E will investigate it.
It will show evidence and uncertainty.
It will ask before saving.
Then it can plan around places I actually saved.
```

That is the product promise to optimize next.
