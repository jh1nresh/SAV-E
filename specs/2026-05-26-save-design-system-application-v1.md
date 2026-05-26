# SAV-E Design System Application V1

> Last updated: 2026-05-26
> Status: reviewed plan for the next native SwiftUI polish PR

## Scope

Apply `DESIGN.md` to the next native SwiftUI polish PR.

This is a SwiftUI implementation plan, not a React or web app plan. The PR should
make SAV-E feel like one coherent product language: Memo elephant, cream notebook,
Map Stamp, Review Clue, Passport, and Evidence Receipt.

## Success Criteria

- Screens touched by the PR visibly follow `DESIGN.md`.
- Users can distinguish Source Clue, Review Candidate, Unsaved Candidate, Map Stamp,
  Visited Map Stamp, Private Review, and Trip Stop.
- Old mixed UI language is removed where this PR touches the screen.
- No parser, backend, TestFlight, deploy, payment, wallet, or social scraping scope
  is added.
- `git diff --check` passes.
- iOS build passes with code signing disabled.
- Key screens are visually checked in simulator.

## Screens To Change

### 1. Sign-In

Files:

- `Wanderly/App/SaveApp.swift`

Change:

- Keep Memo as the first visual anchor.
- Make the background fully notebook/cream.
- Keep the three-step workflow strip: Capture, Review, Save.
- Remove any remaining generic travel-app language.

States:

- Loading sign-in.
- Email submitted, verification code waiting.
- Auth error.
- Disabled submit.

### 2. Onboarding

Files:

- `Wanderly/Views/Onboarding/OnboardingView.swift`

Change:

- Lock the ladder: Source Clue -> Review Candidate -> Map Stamp -> Trip Plan.
- Rename any generic "Candidate" label to "Review Candidate" when space allows.
- Keep one interactive demo card.

States:

- Source Clue.
- Review Candidate.
- Map Stamp.
- Trip Plan.

### 3. Map Shell

Files:

- `Wanderly/Views/Map/MapView.swift`

Change:

- Keep notebook top nav, category filters, Passport button, current location button.
- Make Map Stamp and Review Candidate pins visually distinct at a glance.
- Ensure Review Candidate pins only appear when coordinates are reliable.
- Make Passport review count read as waiting clues.

States:

- No location permission.
- Locating.
- Selected Map Stamp.
- Selected Review Candidate.
- Empty map.
- Route visible.

### 4. Drawer And Search Results

Files:

- `Wanderly/Views/Drawer/AIDrawerView.swift`
- `Wanderly/Views/Drawer/Components/SaveSearchResultsComponent.swift`
- `Wanderly/Views/Drawer/Components/PlaceListComponent.swift`
- `Wanderly/Views/Drawer/Components/NavigationCardComponent.swift`
- `Wanderly/Views/Drawer/Components/TripItineraryComponent.swift`

Change:

- Treat the drawer as SAV-E's command and memory workbench.
- Keep "From your SAV-E" visually above "New / Unsaved".
- Make disabled rows clearly non-actionable.
- For source-only results, show "Needs exact place" as the action.
- For confirmed results, show "Open Map Stamp" as primary.

States:

- Empty saved results.
- Empty new recommendations.
- Loading answer.
- Search error.
- Source Clue.
- Review Candidate.
- Unsaved Candidate.
- Map Stamp.
- Visited Map Stamp.
- Private Review.
- Trip Stop.

### 5. Memory Card And Place Detail

Files:

- `Wanderly/Views/List/PlaceCard.swift`
- `Wanderly/Views/Map/PlaceBottomSheet.swift`
- `Wanderly/Views/Shared/EvidenceLinkList.swift`
- `Wanderly/Views/Shared/SaveMemoryBadge.swift`

Change:

- Place identity first.
- Evidence Receipt compact and secondary.
- Source links clickable when available.
- Delete remains in overflow.
- Do not let raw analysis text become visible card copy.

States:

- Map Stamp.
- Visited Map Stamp.
- Source available.
- Source missing.
- Delete confirmation.
- Delete failed.

### 6. Review Candidate Queue

Files:

- `Wanderly/Views/Drawer/AIDrawerView.swift`
- `Wanderly/ViewModels/AIDrawerViewModel.swift`
- `Wanderly/ViewModels/MapViewModel.swift`

Change:

- Review Candidate detail must say known clues, missing info, and what confirmation
  will do.
- Confirm and reject actions must be explicit.
- Saving without reliable coordinates must stay blocked.

States:

- Candidate with reliable coordinates.
- Candidate without reliable coordinates.
- Confirm in progress.
- Reject in progress.
- Save blocked by missing place identity.
- Network/API error.

### 7. Passport

Files:

- `Wanderly/Views/Profile/ProfileView.swift`
- `Wanderly/Views/Profile/StatsView.swift`
- `Wanderly/Views/Profile/SaveMemoryDebugView.swift`

Change:

- Treat Passport as the user's memory ledger.
- Keep settings secondary to Map Stamps, verified count, cities, and waiting clues.
- Local Memory can remain available, but should read as a tool, not the main product.

States:

- No waiting clues.
- One waiting clue.
- Multiple waiting clues.
- Edit Passport.
- Language/settings controls.

### 8. Share Extension

Files to inspect before implementation:

- Share Extension SwiftUI views under the app target.
- Any App Group pending queue handoff UI.

Change:

- No bottom tabs.
- No full app map chrome.
- Show capture status, extracted clues, and next action.
- Weak evidence becomes Source Clue or Review Candidate, not Map Stamp.

States:

- Capturing.
- Source-only saved.
- Review Candidate created.
- Exact place found.
- Failed extraction.
- App Group write failed.

## Old UI To Cut

- Egg, hatch, hatching copy.
- Plain white full-screen backgrounds in app-owned screens.
- Generic travel bookmark language as primary copy.
- "Instagram Reel" or raw source label as a title when a place name exists.
- Debug/pipeline/evidence-tier paragraphs in primary card bodies.
- Bottom tab bar or full app chrome in Share Extension.
- Destructive buttons as primary visible actions.
- Primary-looking rows that cannot be tapped.
- Fake-coordinate pins.
- Review candidates styled exactly like confirmed saved places.

## State Contract

| State | Visual family | Map behavior | Primary action |
| --- | --- | --- | --- |
| Source Clue | Link/clue badge, notebook page | No pin | Find exact place |
| Review Candidate | Seal/review badge, sky/honey accent | Pin only with reliable coordinates | Confirm or reject |
| Unsaved Candidate | Recommendation/search accent | Optional only if map-originated | Save or inspect |
| Map Stamp | Stamp/seal badge, honey/mint accent | Pin | Navigate or plan |
| Visited Map Stamp | Map Stamp plus visited seal | Pin | Update memory |
| Private Review | Receipt/comment accent | No standalone pin | Add proof |
| Trip Stop | Route accent | Trip context only | Review plan |

## Design Review

Initial rating: 7/10.

Why: the repo already has the right raw pieces: Memo mark, cream notebook tokens,
Map Stamp copy, Passport, source-only/review/saved states, and distinct pins. The
gap is that these decisions live in scattered Swift files, so the next UI PR could
still drift into mixed metaphors or over-decorated cards.

A 10/10 plan specifies:

- Exact screens.
- Exact state coverage.
- Which old UI to remove.
- Which components define the system.
- Verification steps.
- Non-goals, especially no web-app implementation.

After this review, target rating: 9/10. The remaining 1 point requires simulator
screenshots after implementation.

### Pass 1: Information Architecture

Finding: saved memory, review, and recommendations must not compete equally.

Fix in plan:

- Drawer hierarchy is "From your SAV-E" first, "New / Unsaved" second.
- Place details show identity first, Evidence Receipt second.
- Passport makes memory stats primary, settings secondary.

### Pass 2: Interaction States

Finding: weak evidence states are where user trust breaks.

Fix in plan:

- Source Clue, Review Candidate, Unsaved Candidate, Map Stamp, Visited Map Stamp,
  Private Review, and Trip Stop are explicitly listed.
- Candidate without reliable coordinates has a blocked-save state.
- Empty, loading, error, and disabled states are required.

### Pass 3: User Journey

Finding: the emotional arc should be "messy source becomes trusted memory", not
"random cards appear on a map".

Fix in plan:

```text
Share or paste source -> Memo extracts clues -> Review Candidate if uncertain
-> user confirms -> Map Stamp -> Passport records the memory
```

### Pass 4: Specificity

Finding: "polish the UI" is too vague.

Fix in plan:

- File groups are named.
- Component roles are named.
- Copy to remove is named.
- Visual families map to states.

### Pass 5: AI Slop Risk

Finding: the dangerous failure mode is generic cards, gradients, and marketing hero
copy leaking into a native utility app.

Fix in plan:

- No React/web app implementation.
- No generic SaaS card-grid language.
- Cream notebook is the app canvas.
- Cards are reserved for real objects.

### Pass 6: Accessibility And Mobile Ergonomics

Finding: dense mobile UI needs touch and text rules.

Fix in plan:

- 44 pt touch targets.
- State labels cannot rely on color alone.
- Place names wrap before evidence.
- One-handed actions stay in drawers and bottom sheets.

### Pass 7: Implementation Boundaries

Finding: visual polish PRs can accidentally absorb parser, backend, or release work.

Fix in plan:

- Parser/backend/TestFlight/deploy/payment/wallet/social scraping are out of scope.
- Verification is docs diff, iOS build, simulator screenshots.

## Verification Plan

Run after implementation:

```bash
git diff --check
xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO build
```

Visual QA:

- Sign-In.
- Onboarding.
- Map with Map Stamp and Review Candidate.
- Drawer search results with all states.
- Place detail.
- Review Candidate detail.
- Passport.
- Share Extension capture path if the target builds locally.

## Non-Goals

- No React app.
- No frontend-app-builder implementation.
- No backend schema changes.
- No parser or OCR behavior changes.
- No App Store/TestFlight upload.
- No public posting.
- No wallet, chain, receipt publishing, booking, or payment calls.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| Design Consultation | `design-consultation` | Create `DESIGN.md` source of truth | 1 | complete | Locked Memo, cream notebook, Map Stamp, Review Clue, Passport, Evidence Receipt |
| Design Review | `plan-design-review` | Improve next SwiftUI PR plan before implementation | 1 | complete | Added screens, states, cuts, IA, state contract, verification |
| Visual Mockups | gstack designer | Generate concept variants | 1 | unavailable | Designer binary exists, but local OpenAI API key is not configured |
