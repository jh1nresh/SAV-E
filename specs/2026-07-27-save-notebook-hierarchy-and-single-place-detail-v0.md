# SAV-E Notebook Hierarchy and Single Place Detail v0

Date: 2026-07-27
Status: implementation spec
GitHub issue: [#35](https://github.com/jh1nresh/SAV-E/issues/35)
Repo: `/Users/jhinresh/projects/wanderly-current`

## Decision

SAV-E keeps the navigation architecture already restored on `main`:

```text
Global: Home | Saves | Trips | Map
Trip:   Plan | Map | Inbox | Share
```

This slice unifies the visual and interaction hierarchy across Home, Review
Candidate, Saves, and Trip Plan. It also removes the legacy detail-state path so
every saved place, Review Candidate, unsaved map candidate, and social place is
presented by the existing `MapDetailDrawerView` shell.

The user-facing state ladder remains explicit:

```text
Clue -> Review Candidate -> Map Stamp -> Trip Plan
```

These states must not collapse into one generic “saved item.” A clue or Review
Candidate is not a confirmed place, and only a confirmed Map Stamp may become a
Trip stop.

## Customer-paid job

> Give SAV-E a link, understand what still needs confirmation, find the
> confirmed place in Saves, and add it to a Trip without learning multiple UI
> or detail-navigation models.

The value is not a new decorative skin. It is a legible path from uncertain
source evidence to a reusable confirmed place.

## Demand, pricing, and distribution gate

- **Demand proof:** repeated direct founder testing reported inconsistent
  colors, a confusing link-to-review-to-save-to-plan flow, duplicate drawers,
  and unclear tab hierarchy.
- **Pricing/paywall:** unchanged. This is an activation and retention
  prerequisite, not a new paid SKU.
- **First distribution format:** deterministic reviewer-demo screenshots, then
  an internal TestFlight build only after separate deploy approval.
- **Security scan:** N/A. The slice changes SwiftUI presentation and navigation
  convergence only; it adds no new external input, auth, parser, network,
  persistence, secret, schema, or dependency surface.

## Experience principles

### One state, one visual meaning

| State | Meaning | Accent | Primary action |
| --- | --- | --- | --- |
| Clue | Raw source that may not identify one place | muted notebook | Investigate |
| Review Candidate | Likely place still requiring a decision | coral | Confirm candidate or Find exact place |
| Map Stamp | User-confirmed SAV-E place | mint | Add to Trip |
| Trip stop | Confirmed Map Stamp placed in a day/order | honey/coral | Edit schedule |

Color is a reinforcement, not the only distinction. Each state also has a
visible label, icon treatment, copy, and action verb.

### Identity before evidence before action

Every object detail follows:

```text
identity and state
-> known place information
-> evidence / missing information
-> one primary next action
-> secondary actions
```

Photo absence, source absence, and rating absence must not push identity or the
primary action below the fold.

### Notebook content, glass chrome

- Content uses the existing cream dotted canvas and notebook page surfaces.
- Glass stays limited to navigation, tab, drawer, and map-control chrome.
- Object cards do not become transparent sheets over patterned content.
- The map itself remains a map; only its controls may use glass.

## Visual tokens

Use existing tokens only:

- Canvas: `SaveDottedBackground`, `saveNotebookBackground`
- Object surface: `saveNotebookPage`, `savePaper`,
  `saveNotebookPage(...)`, `saveNotebookSurface(...)`
- Primary text: `saveInk`
- Secondary text: `saveMutedText`
- Waiting/review: `saveCoral`, `saveCoralInk`
- Confirmed: `saveMint`
- Action/schedule support: `saveHoney`
- Border: `saveNotebookLine`

Do not add:

- a new color token;
- app-owned pure-white full-screen canvases;
- system-blue primary actions;
- blanket material/glass cards;
- an ad-hoc circle icon when `SaveMemoryBadge` or `SaveIconTile` expresses the
  object state.

## Surface specifications

### 1. Home

Home answers “what should I do next?” in this order:

1. One dominant coral `Paste or share link` action.
2. The current waiting Review count.
3. Confirmed Map Stamp count.
4. At most one Trip to continue.
5. Up to three recent confirmed Map Stamps.

Requirements:

- The capture card uses one notebook surface and one primary button.
- Review uses coral waiting-state treatment.
- Map Stamps use confirmed mint treatment.
- Continue Trip and recent Map Stamp cards use the same notebook surface and
  border grammar.
- Existing identifiers remain unchanged:
  `home.root`, `home.capture`, `home.review`, `home.saves`,
  `home.trip.*`, and `home.recentSaves`.

### 2. Saves

Saves is the confirmed-place library, not a second inbox.

Requirements:

- `Waiting for Review` remains a separate coral entry above the library.
- `Map Stamps` carries a confirmed-state label and count.
- Confirmed rows use `SaveMemoryBadge(state: .saved(category))`.
- The empty state explains that uncertain clues remain in Review and provides
  one capture action.
- Existing identifiers remain unchanged:
  `saves.root`, `saves.review`, and `saves.place.*`.

### 3. Review Candidate

The detail order is:

1. Candidate identity and `Review Candidate` status.
2. Known clues.
3. Missing information.
4. Compact evidence/analysis receipt.
5. One primary action.
6. Keep-source, investigate, wrong-branch, and reject actions as subordinate
   choices.

Primary action:

- Reliable coordinates: `Confirm candidate`.
- Missing reliable coordinates: `Find exact place`.

Requirements:

- Review rows and detail cards use coral review styling, never confirmed Map
  Stamp styling.
- Main cards use notebook surfaces rather than generic material.
- Existing identifiers remain unchanged:
  `drawer.review.contextHero`, `drawer.review.analysisReceipt`,
  `drawer.review.primaryAction`, and `drawer.review.candidate.*`.

### 4. Trip Plan

Trip Plan remains a bounded organizer rather than a full planning dashboard.

Requirements:

- Retain the existing `List`, Day sections, add, edit, remove, and move
  behaviors.
- Each stop row presents a numbered tile, place identity, and subordinate
  time/duration summary.
- Move controls remain at least 44 by 44 points and may move below the identity
  row under accessibility Dynamic Type.
- Saving status uses a readable notebook surface rather than generic material.
- Existing identifiers remain unchanged:
  `trip.tab.*`, `trip.stop.*`, `trip.add.dayPicker`, and editor identifiers.

### 5. Canonical place detail

`MapDetailDrawerView` is the only product detail shell. Its four item types
remain:

- `savedPlace`
- `reviewCandidate`
- `unsavedCandidate`
- `socialPlace`

`SavedMapDetailDrawerContent` is the canonical confirmed-place content.

Confirmed-place action hierarchy:

1. `Add to Trip`
2. AI plan, Maps, and Source
3. related sources and evidence
4. edit and visibility
5. list membership and share
6. delete inside a subordinate menu/confirmation

The exact ordering may adapt to existing data availability, but every entry
route must expose the same capabilities and the same canonical renderer.

Entry routes:

- Home recent save
- Saves row
- Map pin
- Drawer search/saved result
- Trip-adjacent saved-place entry
- Friend receipt after saving

All routes resolve through `MapDetailDrawerItem`; none may set a parallel
`DrawerState.*Detail`.

## Renderer convergence

Remove:

- `DrawerState.placeDetail`
- `DrawerState.reviewCandidateDetail`
- `DrawerState.mapCandidateDetail`
- their detent, navigation-title, navigation-subtitle, and content switches
- the redundant `showPlace`, `showReviewCandidate`, and `showMapCandidate`
  state transitions
- the product callsite of `PlaceBottomSheet`

Change the exact-place failure route to reopen the same canonical Review
Candidate item instead of falling back to a legacy renderer.

Keep:

- `MapDetailDrawerItem` as the selected-object presentation state
- `MapDetailDrawerView` as the one drawer detail shell
- shared photo, info, layout, insight, and action-label primitives currently
  colocated with `PlaceBottomSheet`
- `PlaceDetailView` cleanup out of this slice because it has no runtime
  callsite and is not the active dual-state bug

The old shared-primitives file may retain its current filename in v0. File
renaming is not required to prove one runtime renderer.

## Failure fixtures

1. Empty account: no Review Candidates, no Map Stamps, no Trip.
2. Mixed account: one source-only clue, one map-ready candidate, three Map
   Stamps, and one active Trip.
3. Detail degradation: no photo, no source URL, and no rating.
4. Content stress: long English and Traditional Chinese place names/addresses.
5. Async states: candidate action loading/error and Trip saving.
6. Entry parity: open the same Map Stamp from Home, Saves, Map, and drawer
   search.
7. Exact-search miss: return to the same canonical Review Candidate detail.

## Acceptance criteria

1. Exactly four root tabs remain; exactly four Trip tabs remain; root tabs are
   hidden inside a Trip.
2. Exactly one `drawer.root` exists when capture or detail content is open.
3. Home exposes one each of `home.capture`, `home.review`, and `home.saves`,
   plus at most one suggested Trip.
4. Saves separates Review count from Map Stamp count and retains an actionable
   empty state.
5. Reliable and source-only Review Candidates expose different primary actions
   and cannot be mistaken for Map Stamps.
6. Every confirmed-place entry route exposes one canonical detail root with the
   same action hierarchy.
7. Source-less/photo-less places keep identity and primary actions visible.
8. Long English/CJK content does not hide primary actions; controls remain at
   least 44 points.
9. Trip Plan retains add/edit/remove/reorder behavior and its accessibility
   identifiers.
10. Repository search finds zero legacy `DrawerState.*Detail` render branches
    and zero product callsites of `PlaceBottomSheet`.
11. No backend, parser, auth, persistence, model/schema, dependency, build
    number, or release-setting change appears in the diff.

## Verification contract

### Xcode context receipt

- Project: `SAV-E.xcodeproj`
- Generated-project source: `project.yml`
- Scheme: `SAV-E`
- Target: `SAVE`
- Deployment target: iOS 17
- Local tier: build-only plus test-target compilation
- Destination: `generic/platform=iOS Simulator`
- DerivedData:
  `$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- Selected specialist route: `swiftui-ui-patterns`
- XcodeBuildMCP: unavailable in this session; use the documented `xcodebuild`
  wrapper fallback.
- Simulator: do not boot while free disk remains below the 10 GiB runtime gate.
  Existing SAV-E simulator was verified `Shutdown`.

### Local checks

```bash
git diff --check

scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

When supported, run `build-for-testing` against the same generic destination to
compile unit and UI test targets without booting a simulator.

The PR must pass independent diff review and repository CI. Runtime screenshots
remain explicitly deferred until free space exceeds 10 GiB; that later runtime
gate must use one headless simulator and verify it returns to `Shutdown`.

## Out of scope

- Root-tab or Trip-tab redesign
- A second drawer or new nested detail sheet
- Map behavior or visual redesign
- Friends, Passport, share extension, or companion work
- Parser reliability or related-source discovery behavior
- Auth, persistence, backend, schema, or provider changes
- TREK parity or new trip-planning logic
- New analytics, paywall, pricing, build number, release, TestFlight, or deploy

## Human approval boundary

This spec authorizes an implementation branch and reviewable pull request.
Merge, deploy, TestFlight upload, App Store submission, and public publishing
remain separate explicit user actions.
