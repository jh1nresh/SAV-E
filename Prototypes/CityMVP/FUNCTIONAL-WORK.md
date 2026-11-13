# Function completion before visual tuning

User direction, 2026-11-12: finish the requested functions before further visual
tuning. Continue the existing local CityMVP workstream and Draft 342. Do not
publish, merge, enable Actions, change production services, or install an
unverified build. Existing phone build 144 is not this candidate.

## Current bounded contract

Goal: real local capture, saved-place management, explicitly exchanged friend
recommendations, useful source-aware Guide actions and an actual read-only MCP
protocol path. Keep clue, candidate, saved place and visit distinct.

Scope: prototype sources/tests and `SAVVY_CITY_MVP`-guarded integration. Preserve
the current camera/zoom/photo-pin work, unrelated dirty files, account behavior
and private data. No model calls, scraping, paid services or hosted social writes
are part of local verification.

Done for this slice:

- Local capture is not blocked by remote AI quota. Unfinished drafts persist
  across restart in protected, isolated storage; completion clears only that draft.
- Saved places can reach the existing edit/delete detail and Show on map.
- A sender explicitly selects venue fields and writes a sharing-specific reason.
  A recipient opens the JSON snapshot, chooses items and explicitly confirms saves.
  No private note, rating, visit, photo or author claim is inherited as user truth.
  The UI explains that unsigned snapshots are forwardable and cannot be withdrawn.
- Guide shows original name/address, source statements, private notes and saved
  date separately; address copy, source opening and map opening have real actions.
  Translation uses a supported system path or reports its actual unavailable state.
- Only an explicit venue-only Guide export is available to the local MCP server.
  Initialization, tools/list and tools/call execute over stdio against that export;
  the server cannot read arbitrary files, access the vault, write saves or contact
  providers. Exported source text remains data, never agent instructions.

Verification: source/build checks, negative parser/permission fixtures, isolated
store unit tests and focused native interaction tests. Real external AI client,
language-pack execution, hosted friends and Shanghai SDK remain separate evidence
gaps. A mock or protocol smoke test must not be described as those integrations.

Ownership: controller owns shared integration, MCP, project generation and all
build/runtime resources. `city_scene_ios` owns capture then Guide leaf files;
`render_pin_handoff` owns new friend-exchange files. Leaves cannot redelegate.
Existing sessions are reused; the fresh-context Goldfish lane is unavailable at
this parent session's lifetime limit. Independent reused review remains required.

Human boundary: Amap key is still absent. Do not invent one. Real hosted account
or production changes, publication and any release need their scoped authority.
Local endpoint is a verified candidate, not a release or 90% Anywhere acceptance.

## Verification progress and remaining functional work

The source review found and repaired unsafe MCP request-ID/Unicode handling,
missing external coordinate-system provenance, an overlapping native pin
priority-owner race, and generated prototype source statements entering private
notes. Future source statements use the existing Evidence classification;
historical notes are not migrated.

The first native functional run passed Guide and globe pin checks but failed
restart/editor checks. Actual retained AX evidence showed an unfinished draft
being auto-imported through the onboarding binding. The corrected local App
keeps onboarding empty and binds the editor to its own draft store. Keyboard
Done was added for private-note editing. The next run restored and saved text,
but the verifier had inserted at the caret instead of replacing the old text;
the verifier now explicitly selects all before replacement. Failed runs remain
in `PreviewEvidence/saved-pin-status-20261112`.

Still required beyond this local slice: preserve authorized friend recommendation
context separately from private Place memory so Guide can explain who/why;
live identity/sharing permission and withdrawal verification; a real model-backed
Guide with source/branch checks and readable Chinese-source ingestion; an actual
external AI-client conversation rather than a protocol verifier; Shanghai SDK
connection with the user's future Key; and real-device interaction/performance.
These are functional gaps, not visual tuning. Keep working on them before
returning to facade, glow or pin appearance adjustments.

## Next slice: remember the recommendation, without changing private memory

Chosen behavior: store a protected local sidecar only after a recipient confirms
a selected venue. Associate it with the actual saved Place ID returned by the
confirmation path, including when that path finds an existing save. Retain the
sender-declared label, explicit sharing reason, shared/received dates and source
link as an unsigned copied source statement. It is never authenticated friend
identity, a verified visit, or the recipient's private note.

The sidecar must be bounded, atomically written, excluded from backup and scoped
to the prototype/test namespace. The same export/venue/place confirmation is
idempotent. Changing the copied text creates a separate source version; no
automatic overwrite or network refresh. Invalid/corrupt data is preserved with
an explicit failure. Only current saved identities can expose source cards in
Guide; do not join by name, distance, profile label or business category.

A venue save and its source-context write are separate outcomes. If the venue
save succeeds but context storage fails, show "saved, recommendation details
not kept" and allow retry of the context write without another venue save.
Never report the venue as unsaved after a context-only failure. MCP export
continues to exclude this copied recommendation context and private notes.

Maker: city_scene_ios owns new recommendation-store source/tests. Controller
owns App environment, callback return types, Friends/Guide integration and
runtime. Independent checker: render_pin_handoff, read-only. No new source
writer may edit the other owner's files or redelegate. Endpoint remains local;
no hosted social data, credentials, posting, phone install, Actions or production.

Acceptance: two distinct sources can reference one real save; replay adds no
duplicate context; cancellation creates neither save nor context; context-only
failure preserves the actual save and retries safely; Guide resolves exact
saved IDs and keeps source text separate; unshared/private fields never enter
sidecar/MCP; corruption and size failures never reset an existing file.

## 2026-11-13 recommendation-context checkpoint

The local sidecar, exact saved-ID Guide context and context-only retry are implemented. Latest candidate compiles; units report 166 passed, one simulator protection-attribute skip and zero failures. Native file export/read/confirmation occurred in a retained failed end-to-end run, but complete new-source → restart → Guide acceptance remains pending. The final verifier isolates each source namespace to avoid prior data satisfying assertions. Current picker Cancel automation still fails; after three repair attempts, stop unchanged runtime retries and retain the blocker. See `PreviewEvidence/recommendation-context-20261112/RESULT.md`. No live AI, hosted friend service, phone update, PR publication or overall completion claim.

## Current slice: retrieve retained friend recommendations in Guide

Goal: an explicit Friends’ picks mode can find kept sources by venue, sender label or recommendation reason, then open the exact saved place. This is local deterministic retrieval, clearly labeled; it is not a generated answer or a connected friend feed. Read only exact saved IDs/aliases; never search private notes, ratings, visits or photographs. Matching a venue may show its retained copied sources, while a source-text query shows the specific matching source. A query must not stitch one sender to a different source’s reason. Searching/rendering never writes or calls a model. Explicit forget changes only the copied-source sidecar and updates visible results; it never deletes or edits the saved place. Existing Saved mode, map/camera/pins and current privacy boundaries stay unchanged.

Maker city_scene_ios owns only new search helper and tests; controller owns Agent sheet, project generation and runtime; render_pin_handoff independently reviews the current delta. Reused sessions cannot delegate. Verify same-name/alias/deleted IDs, private-note exclusion, per-source matching and literal untrusted text with focused units, generic simulator build and native Guide mode actions. Local endpoint only; no publishing, phone install, production account/API/usage effects or AI claim.

## 2026-11-13 source-aware Guide result

Friends’ picks now searches retained sources by venue, sender or reason, with exact saved-ID/alias joins and per-source AND matching. A label from one source cannot combine with another source’s reason. The full-height Guide fixes the observed half-sheet/footer interception. Source-marker propagation no longer overrides action identities. Clear/forget have explicit minimum tap areas.

Eight new search tests pass within 174 passed / one simulator file-protection skip / zero failed units. The repaired native flow passes: negative cross-source query, matching copied text, exact saved detail, exact-source forget, immediate result invalidation, remaining independent source and unchanged Saved search. Synthetic-source disk read-back confirms only Bob remains and the existing vault hash is unchanged. The native flow verifies 101 unchanged inputs; four UI/oracle files changed after the unit run, while search/store/coordinator logic and tests remained identical. This is reused independent review, not fresh Goldfish; full file exchange → restart acceptance and live services remain open. Evidence: `PreviewEvidence/guide-retrieval-20261113/RESULT.md`.

## Current slice: bounded Guide AI connection, pending live authority

Implement a real adapter to the existing SAVEGeminiTransport and analysis start/finish lifecycle. The model selects only explicitly selected place/source IDs; the UI quotes the original source and does not show model-authored factual prose. Request review shows the exact chosen names/categories and optional self-declared sender/reason text before sending. Never automatically attach addresses, coordinates, private notes, ratings, photos, visits or other saves. Cap request/prompt/model output, use one model attempt with no repair/fallback, reject unsupported references and ignore cancelled/stale results. Account changes invalidate authorization and responses. No choice saves or edits a Place.

Local prototype configuration is explicit and disabled by default, separate from production API defaults; no guest bootstrap or direct API-key fallback. Metered backend start/finish and proxy usage are supported but must not execute here. Local tests use injected lifecycle and URLProtocol only, proving headers/correlation/quota denial/strict response behavior without network or model charges. A real call still needs a named approved test endpoint/account and scoped provider usage authority. Do not claim a mock is a live Guide or that typed references verify current facts.

city_scene_ios owns new selection contract/tests until released; controller owns client/controller, request-review UI, project and runtime; render_pin_handoff independently reviews the assembled delta. Local endpoint only, no phone install, publishing, Actions, model spending, account/service/schema writes or production changes. Existing map/pins, Saved search and copied-source retrieval remain available.

## 2026-11-13 Guide AI local result

The default-disconnected selection/consent UI and one-attempt existing proxy/analysis adapter are implemented. Strict IDs-only responses, stale/cancel/account protection and current-save handoff pass local checks. Build PASS; same 107 inputs support 192 passed / one simulator protection skip / zero failed units and two passing native flows. URLProtocol traffic is not a live model call. Read-only Railway inventory found production only, so no endpoint, credential or provider usage was enabled. Source review repaired two account/handoff issues; live auth/review-switch and actual model quality remain unverified. See `PreviewEvidence/guide-ai-20261113/RESULT.md` and `GUIDE-AI-CONNECTION.md`. Other functional and Anywhere acceptance gaps remain open.

## Current slice: ordinary map zoom/cold handoff evidence

Current source already promotes native-ground/cloud/context/labels into normal City Lab launches; historical WORKSTREAMS paragraphs predate that promotion. Do not re-promote flags or treat comparison-path screenshots as current ordinary behavior. Inspect with only --inspect-citylab, which leaves route=preview and trace=false. Establish current far-101/arrival failure with real native pinch checkpoints and bounded recording before choosing a renderer change. Preserve single geographic selected-photo owner, sampled <=2pt anchor, saved count, camera freedom and baseline nearby geometry. Readiness/fit/metadata is not visual proof of no cube, no seams or every-frame continuity.

city_scene_ios owns a new observation UI test only; controller owns geometry diagnosis, generator/build/runtime/recording and synthesis; render_pin_handoff will review any resulting renderer patch independently. No production/phone/GitHub/Actions or data writes. Local endpoint is evidence-driven map repair, not an all-world or 90% acceptance claim.

## Current slice: independent native registration observation

Observe raw bundled 101 origin and registered origin through the same MapProxy without changing camera, renderer, registration or saved truth. The normal preview inspector may expose only public landmark coordinate/offset/provenance and optional finite native points; disabled inspections must make no extra projection calls. This is evidence for a coordinate hypothesis, not a coordinate-system fix or no-cube acceptance. Reused city_scene_ios audits other functional gaps; render_pin_handoff independently checks observations and current patch. Controller is sole writer/build/runtime owner.

Xcode receipt: SavvyCityMVP.xcodeproj; scheme/app SavvyCityMVP; CityMVPTests and CityMVPVisualTests; iOS deployment17.0; generic iOS Simulator arm64 build-for-testing using Prototypes/CityMVP/.build under the existing exclusive controller lock. Focused native observation needs borrowed iPhone14Pro simulator06BE9771-5352-4009-9F51-0BEE7708E7EB on iOS26.5; boot headless and verify Shutdown. XcodeBuildMCP unavailable; use direct xcodebuild and the existing bounded runner. Phone ignored, no signing/install, production or publishing. Disk28GiB,10GiB floor; current resource receipt citylab-ordinary-zoom-20261113 owns cache4GiB and evidence256MiB. Verification: compile, focused CityTransitionTests and normal preview native projection observation, frozen-source independent review.

## 2026-11-13 map observation and functional gap inventory

Reused city_scene_ios and render_pin_handoff sessions completed source audit, frozen-baseline evidence review and independent observer review. Fresh Goldfish context remains unavailable at24 lifetime children. Controller observation-only candidate builds;33/33 transition tests and1 normal preview native projection test pass on108 unchanged inputs. Earlier baseline native reciprocal zoom passes but predates observer additions. Registration remains unchanged:515.6m numeric offset and183pt separation at4270m are measured, not proof of a coordinate-system defect or that the northern gray cuboid is101. Renderer repair, seams and current phone acceptance remain open. See PreviewEvidence/ordinary-zoom-20261113/RESULT.md.

Functional priority before visual tuning:

| Work | Current boundary | Next acceptance |
|---|---|---|
| Recommendation exchange | Local real-file native export/import→confirm→restart→visible exact-source Guide PASS; no seeded source, unchanged vault | Cross-device transfer, hosted identity/permissions and revocation remain separate gates |
| Chinese-source Guide | Existing link/OCR/name entry and system translation presentation | Public text, screenshot, unreadable link and branch confirmation end to end |
| Live Guide AI | Default disconnected; typed adapter/consent tests pass | Named approved test endpoint/account and bounded provider/analysis-write authority, then actual semantic completion |
| Friends trust | Unsigned copied sources, no hosted identity/revocation | Authenticated selected-source sharing/permissions and withdrawal product boundary |
| External MCP | Venue-only explicit snapshot; subprocess protocol tests pass | Actual external AI client tool conversation without private-vault exposure |
| Shanghai | Pending configuration, no Key or connected SDK | Amap map/provider coordinates, Jing’an Temple overlay and navigation with future Key |
| Full app loop | Capture/Saved/Passport/Search wiring exists | Same-candidate add→review→save→map/Saved sync→edit/delete and all tab returns |
| Phone/system behavior | Phone still build144; prior candidate only | Same-version installation, real translation pack, auth-switch and motion evidence |

## Current slice: real recommendation-file round trip

Prior goal turn made progress: direct native registration observations and33 focused units passed; no renderer fix was claimed. This slice closes a functional evidence gap before visual tuning. New diagnosis from retained export-roundtrip-r3 native image/hierarchy: the save panel has no visible Cancel button; an AX Other labeled Cancel overlaps the More control. Do not blindly tap that label or repeat app.buttons[Cancel]/Back navigation. Exercise a genuine header drag to dismiss the system sheet, require native filename field gone and Friends Done hittable, and prove no export completion. Then use actual system Save, normal Open a recommendation file, explicit recipient confirmation and restart→exact-source Guide.

Scope: controller owns VisualTests/CityMVPFunctionVisualTests.swift and bounded runtime verifier; no parser/app/map/camera changes planned. Reuse the existing founder/Swift Xcode receipt: SavvyCityMVP.xcodeproj, scheme SavvyCityMVP, iOS17 deployment, generic iOS Simulator arm64 build-for-testing; same exclusive .build cache. Runtime requires real UIKit file exporter/importer behavior on borrowed iPhone14Pro simulator06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5, headless then verified Shutdown. Resource run citylab-friend-file-20261113 owns4GiB cache,192MiB evidence,10GiB floor. All file writes remain On My iPhone/local simulator, no phone/production/network/model/export to external person. Existing reviewer vault is read-back hashed, never reset; only a fresh copied-source namespace may be created by real UI confirmation. Full unit and focused native test plus reused independent review; no fresh Goldfish or new child at24 lifetime limit. Endpoint local evidence, not overall completion.

The first real exporter→normal importer→explicit confirmation→restart native journey now passes. Read-only postcheck re-resolves the app container after XCTest installation changes its UUID; the initial stale-path failure is retained without rerunning native UI. One unseeded source exactly matches the569-byte actual file and existingATT UUID; private-field allowlist/source identity and unchanged vault hash pass. Visual inspection then found an acceptance gap: exists assertions could pass while friend text remained offscreen below private notes. Promote the existing recommendationSources block immediately after place/status, preserving unverified sender language and private memory. Strengthen the verifier to require sender and complete reason hittable and within the actual393×852 initial viewport; no scrolling to manufacture initial visibility. Rebuild and rerun the affected native round trip; unchanged model/unit inputs retain their194PASS/1skip evidence.

## 2026-11-13 real file-exchange result

The actual local system exporter and normal importer now complete explicit confirmation and process-restart persistence. Initial AX-only success was insufficient visually; moved the existing recommendation block beneath place/status and verified the exact nonce-bearing sender and complete reason inside the initial393×852 screen. Current build and1 affected native flow pass; original full195-unit run reports194PASS/1explicit protection skip, with only the two reviewed UI files changed afterward.108 current native inputs unchanged.569-byte exact exported JSON, one unseeded source, saved UUID/source SHA and private-field allowlist correspond; original vault hash unchanged. Reused independent review PASS. Original stale-container postreader failure retained and fixed without a UI retry. See PreviewEvidence/friend-file-20261113/RESULT.md. Hosted friends/trust, live Guide, other functional and Anywhere acceptance gaps remain open; no phone/production/publish actions.

## Current slice: Chinese clues and the remaining legacy review card

Previous turn made progress: real recommendation file exchange and initially visible source are verified. Continue existing Draft342; queue readback still contains342/340/339/325/309, no new PR or Actions. The normal local Capture path uses deterministic reviewCandidatesOrSourceOnly plus on-device Vision, never remote semantic analysis. ReviewCandidateDetailCard still renders PostcardDetailPaper/Atlas fonts in the prototype, unlike the current Capture/Guide forms. Replace only the SAVVY_CITY_MVP rendering with a neutral card while forwarding the same SavePlaceActionResolution, edited name, recovery/reject/source-only callbacks. Clue/candidate is never saved until the original explicit confirmation path succeeds. Keep original Chinese/branch/address and source text; no invented translation, coordinates, distance, checks or source-reading claim.

Controller owns new prototype review view, conditional AIDrawer call, focused OCR/parser units and one normal native Chinese capture→unplaced review→reject flow. Existing map/zoom/dock/source storage/production layout remain untouched. Reused independent review only; no new children. Xcode receipt reused: SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17 deployment, generic iOS Simulator arm64 build-for-testing, exclusive .build cache. Borrowed iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5 is needed for real Vision and native route, headless then Shutdown. Resource receipt citylab-capture-review-20261113: cache4GiB/evidence192MiB/floor10GiB. Use task-generated Chinese OCR images and unique fictitious clue; never fetch that synthetic link, run a model, save a real new place or mutate existing saves. Readback must show original vault preserved after explicit test-clue rejection. Local endpoint only, no phone, signing, publishing or production.

Initial full199-unit run passed198/1explicit protection skip. Native Chinese clue preservation, visible recovery state and explicit rejection worked; the test then incorrectly expected tabs while still pushed in This capture. Retained native hierarchy confirms the real BackButton and no clue left; fix the verifier to go Back before switching tabs, without changing navigation behavior. The screenshot also exposed remaining postcard chrome around the new inner card. Remove the prototype review header/perforation/stamp and full-screen dotted background/count-notice styling, preserving existing Share content and Close callbacks and leaving shipping branches unchanged. Capture-results library and other legacy detail bodies remain separate uncompleted style work; do not claim whole-app parity.

Native-r2 reached Map through the real Back action but the inspector/frame stayed absent. The retained hierarchy proves Map selected and native map visible. MapView.onDisappear cleared both last camera and fitted frame, with no onAppear sampling; reentering without a camera-change event had no projection/scene-label metadata until a drag. Preserve the last observed native camera only, invalidate its fitted frame on disappear, and resample through the current MapProxy on appearance (fall back to the existing bound camera for a new state). No camera target write, animation, origin/101 recenter or old projection reuse. Strengthen native verifier with a real pan, settled camera snapshot, capture/reject/back and exact resumed-camera comparison. This is a newly evidenced lifecycle defect, not a waiver for missing inspector. Existing records remain byte-identical in both retained failed verifiers.

Native-r3 did not reach capture: the new settle oracle used1e-6 for both metres and degrees and timed out. Do not call that an app-return failure. Its absence of retained samples/screenshot at that early assertion is also inadequate evidence. Final bounded verifier correction uses the already-proven ContinuousZoom component units (lat/lon1e-8,distance0.1m,heading/pitch0.01deg), retains every settle sample plus hierarchy before assertion, while preserving unchanged after-return camera and independent native-point2pt gates. No app change for this verifier correction. Native-r4 is the last repair attempt in this slice; if it fails, retain exact blocker and stop runtime retries.

Source review also found SavePlaceShareButton prepares a hosted short link in its on-mount task for valid payloads. The tested unplaced caption has no valid payload, but future valid-place preview must not create production share rows under the local-only boundary. Fence only the automatic prepareShortLink call with !SAVVY_CITY_MVP; retain local immediate share content/reset and explicit system ShareLink. Shipping behavior unchanged. This is a static containment repair, not proof a prior hosted write occurred. Include this changed shared source in current verifier manifests and independent review; no live service test.

## 2026-11-13 Chinese capture checkpoint — native return not accepted

Current prototype review card/header and full-screen background are neutral; original Chinese name/branch/address and unplaced recovery/explicit decision semantics remain. Real generated-image Vision/parser checks pass; full199units report198PASS/1explicit protection skip before the later UI/lifecycle/share-guard changes. Current generic build passes. Native-r2 rendered the neutral card and completed Chinese review/reject/back, but return inspector failed. A provisional fresh-MapProxy resume fix is source-reviewed. Last native-r4 stopped before capture at an8s settle waiter;2 retained camera tuples are identical while AX hierarchy capture cost about19s. This is an observer/app-performance ambiguity, not proof of physical motion or return alignment. Stop retries; no native return PASS, no phone install. All original vault records/bytes and saved count unchanged, no test clue left. See PreviewEvidence/capture-review-20261113/RESULT.md for failed runs, current112-input readback and next bounded latency-vs-native-event diagnostic. Existing hosted-share on-mount preparation is now disabled only under SAVVY_CITY_MVP; immediate local sharing and shipping code remain. Other functional/visual requirements remain open and overall goal stays active.

## Current slice: separate native progress from AX observation latency

Previous goal turn made progress: neutral Chinese review, real local Vision/parser evidence, a source-reviewed map-remount repair, and retained identical-pose/slow-AX evidence. Native return acceptance remains open; do not rerun the same8s waiter. One bounded diagnostic now compares the same normal scene with observation disabled/enabled, directly times a small number of AX reads, and records native camera events/main-actor heartbeats/playback flags only under both explicit inspect flags in a simulator with a validated unique test ID. No renderer/camera/quality changes, default telemetry, user/vault/source names, network, phone or production. Closed event vocabulary,128KiB file/512records/120s bounds, task tmp namespace and no overwrite. Static logger calls must not publish UI state. Native trace is actual MapKit callbacks; remount seed events are separate. Main heartbeat gaps cannot alone establish frame rate.

Controller owns probe, app/map/scene observation hooks and bounded timed-AX verifier. city_scene_ios audits source hot paths read-only; render_pin_handoff independently checks instrumentation/evidence. Existing session budget24, no new children/fresh Goldfish. Reuse Xcode receipt: SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17 deployment, generic simulator arm64 build-for-testing, same exclusive .build cache. Runtime requires borrowed iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5 headless then Shutdown. Run citylab-camera-observer-20261113 owns cache4GiB/evidence192MiB/10GiB floor. No source fixtures/saves are created. Endpoint is causal evidence, then a behavior-preserving fix only if supported; not return/visual/FPS acceptance from a diagnostic PASS.

## Delegated functional repair and observation checkpoint

Two existing agent sessions completed independent scopes: Saved/Passport/Search/
Capture audit and isolated import repair; observation/Guide/Friends/MCP review.
The local Takeout path could swallow its primary-vault error and acknowledge a
non-durable save. The adopted prototype-only repair propagates persistence
failure before publishing Saved state. Shipping/remote mirror behavior is intact.
Two new temporary-vault tests verify corrupt bytes preserved/no false Saved,
durable reopened identity and duplicate replay. Source review passed; controller
executed the tests. Current generic build and all204 CityMVP units pass with
203passed/1explicit simulator protection-attribute skip/0failures.

Paired ordinary native city/pan diagnostics pass with identical115 inputs and
unchanged existing vault bytes. Actual enabled observation produced bounded
native camera/heartbeat records; default/control produced none. Short state
reads did not reproduce the earlier19-second hierarchy delay, and installed
samples did not reproduce stuck SCN playback. No speculative animation or
renderer quality change. Capture-return, continuous zoom/seams, real-device
performance and overall feature acceptance remain open. Details and retained
initial collector failure: PreviewEvidence/camera-observer-20261113/RESULT.md.
No phone install, publishing, merge, Actions or production changes occurred.

## Native return acceptance checkpoint

Paired direct-read observations from the previous slice justify replacing the
failed predicate waiter with bounded directly timed reads, preserving the
original camera/independent native-point gates. This slice edits only
CityMVPCaptureReviewVisualTests.swift, with no app/renderer/camera changes.
Generic builds pass. Real Chinese capture→unplaced review→reject→Back→Map
passes; retained before/after camera and native projections are exactly equal.
A second normal-launch test discovers and selects an existing saved photo pin,
visits Saved/Passport and returns: same identity/state/label, camera and anchor
within original tolerances. Both preserve existing vault bytes/count and leave
no synthetic clue. Borrowed simulator verified Shutdown after each test.

Evidence: PreviewEvidence/map-return-direct-20261113/RESULT.md. This closes the
bounded return evidence gap, not continuous-motion stability or visual parity.
No fresh/reused independent agent is available for the new verifier delta due
the lifecycle/storage cap; independent review remains pending. No phone or
shipping action, main/PR mutation, live provider or Actions change is authorized
by this local checkpoint. Overall goal remains active.

## Normal saved photo-pin pan/zoom/rotation checkpoint

CityPinMotionVisualTests now exercises a normal inspected preview with an
existing saved photo, actual pan, three outward/inward pinches and rotation.
After a retained zero-test selection and pre-connection UIKit runner crash,
native enumeration supplied the exact selector and explicit simulator boot
readiness preceded the actual passing run. No app source was changed to repair
the verifier/environment. Actual run:1passed/0failures,115inputs unchanged,
existing vault bytes/count unchanged. Selection persists at endpoints from
2.9km through11.4km and back2.7km, with on-screen control-anchor2pt gates.
These endpoints do not prove every-frame pixel attachment or frame rate.

Evidence and an83-second original/compact preview are in
PreviewEvidence/pin-motion-normal-20261113/RESULT.md. Sampled frames still expose
native/authored geometry and cloud-boundary differences. Do not claim the
moving jitter, road/seam/cuboid or Anywhere visual acceptance is complete.
Future media capture must account for finalization buffering: the requested
64MiB file stop finalized107.4MiB, within the enclosing192MiB evidence allowance.
Independent verifier review, phone and all broader acceptance gaps remain open.


## Context cuboid ownership and first bounded shape repair

Paired normal-map captures identify the extensive gray outer masses as our
authored context chunks: hiding only that layer removes them with identical
camera/native projections. Added muted per-building vertex colors and two
coarse glazing bands within the existing shared-material spatial batches. The
bundled stadium now has an illustrative curved roof; an actual unconditional
north pan shows it inside the normal map. The large flat northern commercial
roof is not conflated with that stadium. No camera/pin/ground changes were made
for this rendering repair.

Current generic build passes;206units report205PASS/1explicit protection skip,
0failures. Matched default old/new native captures and the actual north pan
pass with115inputs and original vault bytes/count unchanged. Earlier0-test and
optional-pan no-op cases are retained and excluded from the relevant acceptance.
See PreviewEvidence/context-owner-20261113/RESULT.md. New rendering/verifier
independent review remains unavailable at the24-child/storage lifecycle cap;
this is a local candidate, not a shipping-ready or Anywhere-parity claim.
Road/cloud seams, frame-by-frame pin attachment, real phone and the previously
listed functional/provider boundaries remain open. No publishing, Actions,
phone or production action occurred.


## Current slice: complete the normal save/edit/delete journey

Previous turn added evidence and closed the context-render resource receipt;
its rendering review remains pending. Prioritize the missing full functional
loop now. Controller owns only CityMVPFunctionVisualTests.swift and bounded
verification artifacts. Use an explicit unique synthetic Apple map-link clue
through normal Capture, candidate confirmation, map/Saved identity, private-note
edit, process restart, and Delete Place. No seeded pin, prewritten save or
private-record editing. Delete only the generated fixture through real UI;
read back original records by ID and content, retaining failures without reset.
If a failure leaves the clearly tagged fixture, report it rather than deleting
unknown records. No network/model/phone/main/Actions or publishing.

Reuse Xcode receipt: SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17, generic
arm64 Simulator build-for-testing using exclusively locked .build; native
UI on borrowed iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5, headless
boot then Shutdown. XcodeBuildMCP unavailable, direct xcodebuild fallback.
Resource run citylab-full-save-loop-20261113 owns4GiB cache/128MiB evidence/10GiB
floor. Independent review unavailable at child lifecycle/storage limits;
local evidence does not certify release or 90percent Anywhere parity.


## Full-loop evidence exposes new-source/private-note contamination

The third corrected native selector positively ran the current verifier and
rejected both prior synthetic reviews, then normal Capture→explicit Confirm
and save→actual saved pin→Saved→edit→restart executed. The world-view oracle
incorrectly required district render pins after restart; a bounded continuation
re-entered Taipei and resolved the exact retained saved ID. It then exposed
parser prose already in the private-note editor, followed by the inserted note.
Stop the UI repair loop after three repairs. Delete/sync acceptance is not
complete; one explicitly named generated fixture remains in the borrowed
simulator only. Retain all artifacts, no data reset or historical note migration.

New implementation scope: only SAVVY_CITY_MVP's local review confirmation moves
freshly classified candidate prose from the incoming Place.note into existing
additionalSourceEvidence before save/merge. Candidate evidence has no private
user-note field. Shipping and remote behavior stay byte-identical. Existing
private notes, including generated-looking user text, remain untouched. Two
actual parser→review→confirmation temporary-vault regression tests cover source
retention/reopen and matching-save merge/private-note preservation. Rebuild and
run units; do not claim those checks complete the failed native deletion loop.
Same resource run/ownership; independent review unavailable, local candidate only.


## 2026-11-13 full-loop source/private-memory repair checkpoint

Actual UI Capture→explicit save→new map ID→Saved→note edit/restart exposed
source parser prose in the private-note field. Retained R3/r4 intermediate
evidence is not an end-to-end PASS; wrong-caption, verifier identity and
Earth-versus-district oracle failures are preserved. New prototype-only local
review conversion keeps source prose as additional evidence and leaves the
incoming private note empty; existing user notes, shipping and remote branches
are not reinterpreted. Generic build PASS;208units report207PASS/1explicit
protection skip/0failures, including real parser-confirm/reopen and exact
existing-note merge regressions. New app delta has not had native UI acceptance
or independent review.

One tagged generated save remains in the borrowed simulator. The original
three records' raw byte slices reconstruct exactly to the pre-fixture SHA256;
no file reset/migration was used. Next native gate must delete only that known
fixture through real UI, confirm initially empty note on a fresh save, complete
edit/restart/delete and map/Saved synchronization. See
PreviewEvidence/full-save-loop-20261113/RESULT.md. Overall goal incomplete;
no phone/production/publishing/Actions changes.


## Current slice: native acceptance after the provenance repair

Previous goal turn is progress: actual native evidence exposed incoming source
prose in private notes, prototype-only confirmation repaired it, generic build
and208units (207PASS/1explicit skip) passed. This is a new native acceptance of
that changed app, not repetition of the old world-view oracle. Controller owns
CityMVPFunctionVisualTests and this bounded runner. New selector and attachment
identity must prove current verifier execution. Delete only the exact retained
generated save through normal UI, then fresh Capture→unconfirmed candidate→
explicit save→actual map/Saved identity→initially empty private note→write note→
restart→Taipei same ID/note→normal deletion→Saved/Map/Passport consistency.
Readback must restore the original three records' exact pre-fixture SHA256.
No seeded save, vault reset or historical note reclassification.

Reuse Xcode context: SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17, generic
Simulator arm64 build-for-testing; exclusively locked existing .build. Borrowed
iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5 headless boot then
verified Shutdown. Direct xcodebuild because XcodeBuildMCP unavailable. Resource
run citylab-save-memory-acceptance-20261113:4GiB cache/128MiB evidence/10GiB floor.
Only UI verifier changed since passing units; reuse app/logic evidence while
inputs stay equal. No phone/main/PR/Actions/provider/production changes. Local
endpoint only; independent review remains unavailable at existing lifecycle cap.


## Source/private-note native lifecycle acceptance

After the actual provenance repair, a fresh normal Capture→explicit confirmation
→new map/Saved ID→initially empty private note→edit/save→restart→same Taipei pin
ID/exact note→Delete Place→Saved/Passport/Map return now passes natively. One
retained failure was an outgoing AX close node being queried during completed
dismissal; terminal Saved screenshot and exact restored vault prove data delete
already worked. The verifier now awaits detail-root disappearance before root
navigation. No app change was made for that observer repair.

Passing native-r2:1PASS/0failures,115inputs unchanged, old/new generated fixtures
absent, original3record vault SHA256 restored exactly. Generic build PASS. App
and unit inputs still match the preceding208units (207PASS/1explicit protection
skip/0failures); only the UI verifier changed. See
PreviewEvidence/save-memory-acceptance-20261113/RESULT.md. Source/private-memory
repair has bounded native acceptance; independent review and phone remain open.
The actual Saved detail screenshots still show cream/scalloped/large-brand
legacy presentation. Next UI work should replace that prototype surface while
preserving management, visit/source state, planning/list actions and callbacks.
Overall Anywhere goal remains incomplete; no publishing/Actions/production.


## Current slice: remove legacy Saved detail presentation

Previous turn is progress: the actual repaired save/private-note/edit/restart/
delete and three-tab return journey passed with exact original vault restored.
Native screenshots prove Saved detail still has cream paper, scallops, postal
seal, oversized brand artwork and dense tiny controls, unlike the current
neutral Saved/Passport/Capture surfaces. Use existing CityMVPFormStyle tokens
under SAVVY_CITY_MVP, the authorized standalone direction; do not change the
shipping Ink direction, global palette, current map, camera, pins or dock.

Controller owns AIDrawerView's prototype Saved header/body/editor/list styling,
PlaceBasicInfoPanel presentation, RelatedPlaceSourcesPanel presentation and
SaveVisitIntentChooser prototype styling. Keep existing confirmation, edit,
private note, explicit unverified visit intent, delete, source/identity guards,
photos/attribution, share, map/navigation, trip/plan and list callbacks and all
fields. No source truth writes from opening/rendering. Five-second state stays
Map Stamp Saved, with original name/address and private memory distinct from
source statements. Do not remove actions to make the page prettier.

Visual anchors at393x852: neutral fixed header with44pt share/close; large
wrapping venue title and circular/rounded real image; clear Saved state; primary
map/navigation action;44pt+ intent/edit controls; separate notes/facts/sources/
organization cards. No paper texture, perforations, rotated photo, brand stamp,
colored fake verification or invented photos. Match existing non-map Form
surfaces and keep Anywhere map/dock unchanged.

Reuse Xcode receipt: SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17, generic
Simulator arm64 build-for-testing, exclusively owned existing .build. UI and
full units on one borrowed iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/
iOS26.5, headless then Shutdown. Resource run citylab-saved-detail-style-20261113
owns4GiB cache/128MiB evidence/10GiB floor. Evidence: generic build, current full
units, normal Saved detail day/night and actual management loop; preserve exact
original3record vault. New runtime frame warning still needs causal evidence,
not speculative renderer changes. Independent review unavailable at lifecycle
cap; candidate remains local, no phone/main/PR/Actions/provider/production.


## Current bounded parallel repair batch

The user explicitly renewed multi-agent execution. Three fresh-context native
leaves cover map handoff, photo-pin continuity and independent source review;
makers return scratch patches, never share source/build/device ownership. This
batch uses a bounded lifecycle allowance of27total children and1213080649bytes
(three new leaves, no variants or redelegation). Controller alone promotes and
verifies patches. Local-only endpoint; no publication/phone/Actions/production.

The source-reviewed candidates correct fallback head remount scale and a
partially missing boundary-cloud projection failing to request the existing
one-shot refresh. Do not claim these solve native column/ground seams or
every-frame drift. Acceptance: reproduce the claimed failure natively before promotion, then run
full prototype units and generic build. The cloud regression fails8assertions
on baseline; the pin ImageRenderer regression passes baseline and is therefore
non-discriminating. Pin patch and added pixel test were withheld; no pin source
change was promoted. The cloud-only repair is now undergoing integrated units.
Saved detail current AX and normal day/night checks pass with the exact original
vault restored. The first AX failure was strict floating-point44comparison;
only0.001pt rounding tolerance was added to the verifier. Existing mutation and
shipping paths remain intact by independent source review.


The three fresh leaves completed: map recovery patch adopted after independent
source review; pin patch no-op after native baseline contradicted its proposed
verifier; Saved source review PASS. Fresh review covers only named frozen deltas,
not the broad accumulated candidate. Lifecycle27total/27completed/0active,
1082737252child bytes at fan-in. No agent owned a runtime resource.


Final local batch:209native units (208PASS/1explicit protection skip/0fail),
current generic build PASS. Independent final readback PASS across10source
hashes; cloud adopted, pin no-op. AX and normal day/night PASS match current
Saved UI. Lifecycle resource receipt closed PASS with zero violations. See
PreviewEvidence/saved-detail-style-20261113/RESULT.md for exact proof limits.


## Next discriminator: independent rendered far pin reference

Previous batch made concrete progress in Saved UI/AX and partial cloud recovery.
Do not adopt the unconfirmed remount patch. Controller owns a simulator-only
normal-preview native Map Annotation magenta ring at selected anchor.coordinate
(no repeated registration), gated by explicit inspect+reference flags, city,
distance>9500, projection nil, scene opacity0 and contact opacity0. This excludes
intentional roof blending. Actual selected existing saved photo, slow pan and
short normal-speed video compare rendered pin/ring pixels; metadata supplies
scope only, never measured positions. Missing/occluded/ambiguous frames reject.
No saved fixture or user-data writes; vault hash must remain exact.

Reused Xcode receipt: root SavvyCityMVP.xcodeproj / SavvyCityMVP, iOS17 deployment,
generic arm64 Simulator build-for-testing, locked existing .build4GiB. Focused
UI on borrowed iPhone14Pro06BE9771-5352-4009-9F51-0BEE7708E7EB/iOS26.5, headless
then Shutdown. Direct xcodebuild, no XcodeBuildMCP available. Evidence128MiB,
10GiB floor, resource run citylab-native-pin-reference-20261113. Existing phone
connection reset by peer; physical acceptance unavailable, no install/release.
Leaves reused: map worker checked coordinate contract, pin worker owns scratch
pixel analyzer, controller source/runtime, independent checker reviews gate.
No production/main/Actions/push/provider/model/credential change.


Native far reference found3measuredframes offset8.39–8.43pt;24/29frames
measurable,5gaps. Independent replay of original pixels confirms displacement;
precise scheduling cause remains an inference. Adopt smallest owner repair:
cloud-handoff frames>=existing9000mprojectionCutoff use existing native saved/
selected annotations; near projected ownership unchanged, nilprojection never
switches owner. All consumers share one distancepredicate; no coordinate/photo/
identity mutation. Historical noncloud comparison unchanged. Verify current
210prototype units, same guarded pixelclip and existing near/far/return/rotation
selected-photo journey. Far inspector sampledpoint remains MapProxy data, never
use it as native renderedheadposition. Maker scratchonly; controller integrated
4filepatch; independent review/current runtime pending.


## Far pin repair verified locally

Existing far sampled-overlay presentation showed8.43pt relative pixel drift.
Native far ownership now measures60/60encodedframes with maximum1.83pt,
0violations at unchanged2pt threshold and57pt actualreferenceexcursion.
Unique-selector/marker test proves physicalempty→exactUUID native reselection;
near/far/return/rotation endpointjourney alsoPASS.210prototypeunits209PASS/
1explicitprotection skip/0fail; app/unitinputsunchanged afterUIobserverupdates.
All current246inputs/frozenappUIbinaries match finalnative runs; installed
simulatorbinaries matchfrozenhashes. Originalvault exactrestored, no phone/main/
Actions/publishing/provider calls. See PreviewEvidence/native-pin-reference-20261113/RESULT.md.

Remaining actual scope: exact9000m ownershiptransition motion, nearroof-contact
continuouspixelalignment, cloud/road/nativecolumnseams, full101–CityHall street
realism/traffic and remaining non-map candidate/social presentation. Native
review/unsaved/social pin views still use legacy DefaultPOIMarker paths; next
local UI pass should preserve saved/review/unsaved/social state while adopting
accepted city circularartwork hierarchy. Live Guide/friend/MCPclient/ShanghaiKey
and same-version phone acceptance remain separate functional requirements.


## Native unsaved-state pin presentation

Previous turn delivered measured far-pin repair; keep camera/roof/far-owner
unchanged. This slice replaces only CityMVP Review/search/shared native artwork
with existing circular head plus distinct visible localized badges/captions.
Saved/visited truth, source language, reliable-coordinate filters and original
callbacks/IDs remain. Shipping legacy branches stay exact; globalpalette and
core CityPinArtwork/raster unchanged. A140x124nativeframe uses contact72/124,
so captions extend below the geography without moving the point.

Maker fresh leaf owns only new StatePin artwork; controller owns integration,
explicit simulator fixture and verifier. Fresh independent source checker follows.
The fixture is loudly labeled synthetic, simulator-only, both explicitinspect
flags plus validuniqueUUID; noauth/VM/vault objects or Save actions. It verifies
actual native annotation layout/day/night/originaltitle/44pttouch callbacks, not
real social feeds or save confirmation. Normal real-saved near/far/return test
and originalvaultreadback preserve previous contracts separately.

Reuse Xcode receipt: root SavvyCityMVP.xcodeproj/scheme SavvyCityMVP, iOS17,
genericarm64Simulator build-for-testing. Oneborrowed iPhone14Pro06BE9771-5352-
4009-9F51-0BEE7708E7EB/iOS26.5 headless thenShutdown. Lockedexisting.build4GiB,
evidence128MiB,10GiBfloor; run citylab-native-pin-states-20261113. DirectCLI,
XcodeBuildMCP unavailable. No phone/main/Actions/push/provider/model/credentials.
Localartifact endpoint; fullAnywheregoal and nearcandidateocclusion remainopen.


Native state layout r3 passes both languages and actual day/night screenshots,
all8physical callbacks and fixed-frame selection anchors. Initial grid offscreen
and fixture palette/teardown errors are retained in evidence, not counted PASS.
Normal saved journey found intermittent ATT4FUN→CityHall selection during first
inward native pinch. Callback-source observation added, max8identifier-only
entries behind explicit inspector. Same-selector replay omitted new observation
attachments despite compiled strings; not accepted as diagnostic proof. Unique
V2method/marker plus installed app/UI/unit binary readback now required.
Current native-pin-state acceptance remains pending this regression diagnosis.

Parallel leaf prepared Friends-sheet app-copy localization in unique scratch:
/private/tmp/citymvp-friends-localization.sav7TI/CityMVPFriendExchangeSheet.swift
SHA2561f80f9ff11d8192e76de0c45fef29821b1a7c8512a554485d297048f68ea9be4.
Independent review caught/repaired reachable app-owned cap/storage errors; revised
sourcePASS, build/runtimepending and not yet promoted into shared source.
Raw sender/reason/place/address/URL/schema/callback/state preserved. This does
not establish authenticated friends, real GuideAI, externalMCPclient or AmapKey.


## Native gesture + state pins / Friends copy local acceptance
Unique input V2 reproduced native-saved-Button activation on inward pinch.
Normal root now uses same native artwork with passive44pt semantic head and
existing map tap router; all9phase motion endpoints plus actualfar44pt tap/
exactUUID reselection PASS. Shipping/embedded Button/camera/art/threshold unchanged.
Final248inputs/compiled+installed3binaries match current runtime;210units209PASS/
1protection skip/0fail; originalvault exact. State-layout3 screenshots reused only
for unchanged fixturebranch/artwork/verifier, not identicalcurrentwholeinput claim.
Friends localization promoted/reviewed; actual2languageUI/rawdraft/Done PASS.
Knownlimits: densecardcollision, hiddennativehost eligibility, onefieldfocusframe
warning, inmodalswitch/livefriends/GuideAI/externalMCP/AmapKey/phone remainunproven.
See PreviewEvidence/native-pin-states-20261113/RESULT.md and preview.html.
Main evidence bound explicitly expanded256MiB; retained diagnosticarchive128MiB,
noartifactdeletion. Resourcefloor10GiB/cache4GiB; closeout stillrequired.

Resource run citylab-native-pin-states-20261113 closedPASS/0violations,
24.4GiBfree, deviceShutdown, matchinglocksreleased, noactivechildren.
This closes onlynativegesture/statepin/Friendscopy acceptance, notwholegoal.
