# Keep Map search and Review resolution at the intended place

Protocol: codex-grokbot-v1
Task-ID: jh1nresh/SAV-E:map-review-location-repair-20260907
Execution: ready
Mode: engineering
Packet-Revision: 1
Target-Repo: jh1nresh/SAV-E
Implementation-Base-SHA: 665e9c284f94a79fd60021b5bcde658da8cf010f
Executor: Tim
Return-Target: this planning PR

## Outcome and observed failure

Maintenance of the existing capture -> review -> saved place loop. Founder
reports that searching 奶茶, 酒吧 or 咖啡 returns US venues and moves the camera
toward Africa; other category queries may fail too. Review's map preview
sometimes zooms to an unrelated area, Find exact place can crash, and saving
an exact result through Map can leave its source item in Review. Tapping the
collapsed Map search shelf must open the full-height editor with keyboard;
dragging the drawer must resize without requesting keyboard focus. 台北 and
臺北 must match each other without altering stored names/addresses.

Demand proof: direct founder dogfood report on 2026-09-07. Pricing/paywall and
distribution experiments: N/A, maintenance. Delivery format: separate atomic
engineering PR plus reproducible test evidence; app distribution remains gated.

## Verified code findings (not yet runtime proof)

- `MapViewModel.mapCandidateSearchCenter()` chooses selected saved place, then
  first saved place, then 37.7749/-122.4194. `searchMapPlaces` uses it instead of
  the visible map/current location. `MapView` does not report camera viewport.
- `focusCameraOnMapCandidates` averages min/max latitudes/longitudes across
  every returned candidate. Global outliers/dateline results can center the
  camera far from all useful results. It also lacks a coordinate validity gate.
- `prepareMapCandidatesForDrawerQuery` exact branch searches with `near: nil`.
- `ReviewCandidateDetailCard` passes `onFindExactPlace` into the hero map tap,
  so even a reliable known candidate starts a new, potentially global search.
- `ContentView.openExactSearch` dismisses its cover, changes navigation and
  starts an asynchronous search. Empty results reopen plain Map search, whose
  `searchMapPlaces` clears `exactSearchResolution`. Investigate this connection
  loss and presentation lifecycle as hypotheses; do not claim a reproduced
  native crash from static inspection alone.
- `saveReviewCandidateAsPlace` and `saveMapCandidateAsPlace` already contain
  deduplication and exact-search reconciliation. Preserve those protections;
  find the missing caller/context path instead of deleting existing logic.
- `SaveMapDrawerPanel` calls `onExpand(false)` for the search-shelf tap as well
  as drag. `ContentView` already chooses `.large` when focus is requested.
- Saved-result matching in `SaveMapSearchContent` uses raw contains;
  `SaveSearchIntentParser` recognizes 台北 but misses 臺北 in one city branch.

## Allowed-Paths and ownership

Tim owns the following files for this Task-ID. Codex retains the UX decisions
below and performs advisory review; no second writer is authorized.

- SAV-E/ViewModels/MapViewModel.swift
- SAV-E/Views/Map/MapView.swift
- SAV-E/Views/Map/SaveMapDrawerPanel.swift
- SAV-E/App/ContentView.swift (Map/Review navigation and focus only)
- SAV-E/Views/Drawer/AIDrawerView.swift (Review/map action wiring only)
- SAV-E/Services/GooglePlacesService.swift (search coordinate validation only,
  if needed; no endpoint/credential/provider migration)
- SAV-E/Services/SaveSearchIntentParser.swift
- SAV-E/Services/SaveSearchController.swift
- SAV-E/Models/SaveSearchModels.swift
- SAV-E/Services/PendingPlaceImportService.swift (candidate query/map identity
  helper only; no import pipeline rewrite)
- SAV-E/App/SaveChromePresentation.swift (existing SaveChromeNavigation
  coordinate and presentation helpers only)
- Tests/SocialPlacePipelineTests/ (only focused Map/Review/search regressions)
- Tests/SAVEUITests/ (only focused Map/Review/search/focus regressions)
- DESIGN.md (only document the explicit tap-versus-drag rule if needed)

If a small shared pure helper is necessary, place it in the nearest existing
allowed file. No new dependency or project/workflow edit. Confirm actual caller
paths with rg before modifying. Any required additional file needs a bounded
scope amendment from Codex; do not silently widen ownership.

## Decisions and acceptance

1. Generic searches use the user's current visible map area, including after
   panning. A valid current location can initialize search when no viewport is
   available. Do not silently substitute an arbitrary saved venue or the US.
   Without a trustworthy anchor, keep the camera and offer a clear locate or
   city/address next step. Explicit destination queries can search elsewhere.
2. Reject non-finite/out-of-range/placeholder coordinates before rendering or
   camera updates. Keep existing WGS84/provider safety boundaries. Do not clamp
   a bad coordinate into a plausible location. Never pin Source Clues.
3. Local category results must remain relevant to the chosen search area.
   Do not let a distant outlier move the camera. Exact search may return
   ambiguous alternatives; keep them reviewable, focus a sensible local set or
   selected candidate, and do not average continents or cross-dateline bounds.
   No-result/provider error preserves the current camera and original clue.
4. Tapping a Review map with reliable coordinates focuses that exact candidate
   without re-resolving it. A source-only/unreliable clue gets Find exact place.
   A map view/tap does not confirm or save a candidate.
5. Find exact place works from full-screen Review and the drawer. Dismissal,
   tab transition, keyboard and async result delivery cannot race a presentation
   or reopen a stale detail. Cancellation, back, retry, empty results and rapid
   successive searches do not crash or let stale work steal the camera.
6. Saving a result selected to resolve a specific Review clue creates/merges
   exactly one Map Stamp, retains source evidence, and retires that source clue
   in local and remote state only after persistence succeeds. Retrying after
   failure is safe. An unrelated later map save must not retire a prior clue.
   Do not merge records just because their display names match.
7. Tap collapsed search shelf -> full-height existing panel + focused text
   field + keyboard. Drag handle/panel -> staged resize, no focus request.
   Preserve the single in-tree panel; no second sheet. Resize-handle tap remains
   a resize control. Review details must still show the existing Investigate
   action and permit scrolling to it; restore access if the new layout hides it.
8. 台北/臺北 matching works both ways for saved results and search location
   intent. Preserve original displayed/stored text and avoid broad unrelated
   character transliteration or aliases that distort venue names.

## Failure fixtures and verification

Freeze a failing regression before fixing the behavior when executable on the
worker. Use synthetic public-place coordinates, never personal saved data.

- Taipei viewport + first saved US venue + each of 奶茶/酒吧/咖啡; also a generic
  non-food category and pan to a different city. Assert provider anchor and
  result/camera behavior, not just generated text.
- Near Taipei result plus US outlier; opposite sides of the dateline; empty
  result; NaN/infinity/out-of-range/0,0. No invalid map region or continental fit.
- Reliable Review map tap causes no provider search and keeps the coordinate.
- Exact search empty -> typed refinement -> save; confirm on Review vs Map;
  already-saved venue; persistence failure then retry; two identical display
  names at different addresses; stale result after cancellation/unrelated search.
- Tap vs drag keyboard/UI evidence and repeated Review -> exact search -> back.
- Search 台北 against 臺北 addresses and the reverse.

Must-Read: AGENTS.md, DESIGN.md Map/Drawer/Review/State sections,
SAV-E/Extensions/Color+Theme.swift, all changed code plus its immediate
callers, SaveChromeNavigation, existing coordinate/search/dedup tests,
scripts/select-ios-tests.py (read only), and the canonical protocol issue.

Tools: Tim must inspect the actual available Cursor CloudAgent tool schema,
launch exactly one agent with action=launch, repo=jh1nresh/SAV-E and
starting_ref=Implementation-Base-SHA, passing this entire packet. Preserve
configured model defaults. Worker terminal cwd is its cloned SAV-E root.
Use rg, git diff and the repository scripts; never reconstruct secrets.

Commands from repository root:

```sh
git diff --check
scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
```

Use the existing Xcode scheme `SAV-E` and test target `SAVETests` for affected
classes and all required CI units; discover actual class names, record the
exact executed commands in the return packet. The root Package.swift is an
iOS package, not a runnable macOS test target: do not claim `swift test` proof.
Native UI crash/focus proof requires one exclusively owned headless simulator
or canonical CI runtime evidence; do not open Simulator.app. Check >=10 GiB
free before runtime, reuse SAVE-Codex DerivedData, and shut down any simulator
this task boots with readback. If the remote environment lacks Xcode, say so
and use canonical CI/local authorized runtime verification; source assertions
alone do not prove a crash fixed. Do not loosen CI visual parity (0.90), five-tab
smoke, full-unit, or shared-navigation integration requirements.

## Boundaries, stop conditions and deliverable

No auth, payment, retention, migration, deployment, signing, analytics or
private/public visibility changes. Do not issue production writes or transmit
private user locations/links in logs/tests. Preserve saved data and untracked
local files; all implementation is in an isolated branch/worktree.

Stop on conflicting owner, missing required product/privacy decision, required
scope expansion, unavailable credential, three unsuccessful repair attempts,
or low-space runtime gate. Request exact failing link/build as supplemental
evidence, but deterministic map fixes do not depend on receiving them.

Deliver one separate engineering PR linked here, exact implementation head,
baseline/final test evidence, runtime evidence or explicit residual, and Judge
verdict on the same head as passing CI. Elon accepts and closes this RFD;
NEVER merge this planning PR. Route review to 森貝爾. Founder authorized these
repairs and the standing engineering route; merge only under applicable
recorded founder authorization and canonical exact-head gates, otherwise
return merge-ready. No TestFlight, App Store, production deployment, credential
change or broad cleanup is authorized by this packet.

Queue: no open SAV-E implementation PRs at 2026-09-07 intake. This is the first
repair. Plan conversation/legacy entry migration follows this task because it
shares ContentView/AIDrawerView. Keep at most two active tasks; do not launch
the follow-up against these owned files before this writer is released.
