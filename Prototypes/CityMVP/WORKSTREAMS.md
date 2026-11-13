# City Lab workstreams

Local integration plan, 2026-11-11. This extends the existing City Lab task and
Draft PR 342; it does not create six shipping tasks. Production, Actions,
publishing, signing and installation are outside this batch.

## Accepted direction

Map-first navigation is Saved / globe Map / Passport. Anywhere is the map,
photo-pin and zoom reference. The approved Ramin reference applies to other
surfaces. Keep the moving glass lens, continuous icon magnification, spring
settling and blue-white navigation glow. Retain Reduce Motion and Reduce
Transparency. Only explicit user confirmation creates a Map Stamp.

The current source has working local gesture tests and a working local dock
test. The facade budget still fails at 26 against 24. The latest far-map image
is washed out and has duplicate labels. These are open failures, not readiness.

## Work breakdown

| Workstream | Required result | First bounded action | Owner |
| --- | --- | --- | --- |
| 1. Map and 3D handoff | No duplicate ground, native tower column, broken roads or camera jump; Apple Maps outside mainland China, Amap configuration for mainland China | Create an isolated native-only MapKit overlay experiment; compare native building suppression before changing working rendering | render_pin_handoff; controller owns integration and runtime |
| 2. Photo pins | Circular photos with restrained pop/settle motion; geographic anchor and selection remain stable through pan, pinch, rotation and return | Preserve passing selection fixture; inspect any proposed map change against the same fixture | Controller; independent Goldfish |
| 3. Xinyi streets | Distinct facades and shops, detailed road/sidewalk, trees, shadows, moving cars and day/night in the 101–City Hall corridor | Keep existing geometry; resolve the 26/24 material budget without removing variants or disabling mip filtering before expanding assets | Controller after map experiment |
| 4. Navigation | Saved / globe / Passport switch stays responsive with lens, glow and interrupted transitions | Audit current dock and retained-page implementation; return a reproduction and repair specification before edits | ui_capture_search_passport |
| 5. Non-map UI | Saved, Passport, Search and Add follow the approved hierarchy with readable forms and real actions | Audit current changed paths and focused UI test coverage; return exact gaps without speculative repairs | ui_capture_search_passport |
| 6. Guide and friends | Local guide for foreign visitors, authorized friend sharing and explicit selection, source/date distinctions; future MCP boundary stated | Audit GUIDE-AND-FRIENDS.md against the current local-only sheet and produce executable next-phase gaps | Fresh Goldfish; controller owns future product implementation |

## Implementation plan for this batch

One source writer and one read-only interface auditor work concurrently. Neither may
compile, run a simulator, sign, install, commit, push, contact others or
redelegate. The controller is the only project-generator, build and runtime
owner. Existing dirty changes are task-owned and must be preserved.

### Native map experiment

Create `Sources/CityNativeOverlayProbe.swift` and
`VisualTests/CityNativeOverlayProbeTests.swift`. The controller may modify
`Sources/CityMVPApp.swift` only to route an explicit debug launch argument to
the probe. Normal launch must retain ContentView and existing storage.

The explicit launch argument is `--verify-native-overlay-probe`; it routes only
the prototype app to `CityNativeOverlayProbe`. Normal launch is unchanged.
The probe has no SceneKit, snapshot backing, cloud veil or custom pins. Use
`.standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll)`.
SwiftUI's non-muted emphasis is `.automatic`; UIKit's `.default` spelling is
not a SwiftUI API.
Do not modify the live map's default `showsBuildings`; the variable being tested
is overlay placement, not elevation or the building flag. Use the
existing registration resolver and 101 podium footprint. Failure to resolve
registration shows an error and Retry; never guess an offset. Compare no
overlay, aboveRoads at alpha 0.01, opaque aboveRoads and opaque aboveLabels.
Use neutral gray fill at opacity 1 or 0.01, no stroke. For each east/north
podium point, convert with `CityDistrictCamera.coordinate(x: point.x,
z: -point.y)`, then `registration.mapCoordinate`. Camera center is
`registration.mapCoordinate(CityDistrictCamera.coordinate(x: 0, z: 0))`.
Use public MapKit APIs, fixed cameras at 1450 and 4692 metres, heading 20,
pitch 35, and retain native credits. Require an observed camera-change end
matching distance within 2% and angles within 1 degree, then a two-second
settle before capture. Any pitch clamp is a recorded failure to meet the
fixture, not silent success. Wait at most 30 seconds per state, and capture
the error frame before failing. Report exact mode/camera/readiness for
each screenshot. Keep controls outside the tower region. A false property
getter or a nonblank screenshot alone is not a visual pass.

Build with the generated SavvyCityMVP project, generic iOS Simulator, arm64,
Debug and code signing disabled. Run focused probe UI tests only after a
successful build and resource preflight. Compare actual iOS captures; do not
promote black AppKit captures or assume an overlay removes a native building.
Run `CityMVPVisualTests/CityNativeOverlayProbeTests/testNativeOverlayModes`
for all eight states, plus a registration failure/retry test using explicit
`--probe-registration-fails-once`: the first resolution returns nil without
network, Retry invokes the real resolver. Run the existing normal-launch
dock test to check routing isolation. Native extrusion, flat footprint, road
visibility and retained credits are assessed separately in actual captures.
Failure to suppress extrusion is a valid experiment result, not a repair PASS.
An experiment failure leaves normal rendering unchanged.

### Interface repair

This phase is read-only. Inspect the current dock, retained pages, Search and
Capture consumers. Return a demonstrated defect, its exact affected files,
proposed logic change and executable acceptance before any repair. The
controller must accept that bounded specification before granting writes.
Potential future paths are `Sources/CityMVPBottomBar.swift`,
`Sources/CityMVPRootPages.swift`, `Sources/CityMVPAgentSheet.swift` and
`Sources/CityMVPFormCapture.swift`. Legacy consumers remain outside this phase.
No changes to map geometry,
camera, pin routing, global theme, production navigation or authentication.
Keep the existing local search truthful; do not introduce pretend friends,
recommendations, translations, model calls or working MCP claims.

Return evidence and focused verification gaps; no change is preferable to
speculative churn. A future accepted non-map repair must pass the generic
build and existing `testCaptureDraftAndPassportInformation` and
`testSlidingDockKeepsMapCameraAndSelection` checks; exact current selectors
must be confirmed before granting that repair. Existing sequential idle taps
do not prove interruption behavior: that needs a separately specified burst
input test and normal-speed recording, including Reduce Motion/Transparency.

### Independent review and delivery

Fresh-context Goldfish reads its installed persona, implementation-readiness
standard, this plan and an explicit code/evidence reading list. Its first task
is read-only readiness review; adopted source later requires frozen-diff and
real-verification review. Missing evidence stays pending.

Local endpoint: a reviewable probe or repair with evidence, not a claim that
all six workstreams or Anywhere similarity are finished. No new PR, merge,
Actions enablement, release or production mutation. Resources need exclusive
ownership, bounded caches and verified simulator shutdown. Below 10 GiB free,
stop before new runtime work unless the user explicitly accepts that risk.

## First batch results

The isolated probe and normal-launch dock check pass their focused runtime
tests. The eight native captures do not remove the tall 101 column: opaque
overlays add a gray ground polygon instead. Do not promote that mechanism into
normal rendering. See PreviewEvidence/native-overlay-20261111/verification.md.

The interface audit made no source edits. Interrupted transitions still need
direct motion evidence; idle-separated taps do not prove that behavior.

The street-detail investigator found a public SceneKit custom-texture route
for merging retail batches without an atlas: four independent day/light pairs,
eight SCNMaterialProperty textures, a per-vertex variant carrier and surface
sampling before Lambert lighting. This remains a proposed rendering probe,
not an accepted source change. It must preserve phase/repeat, linear mipmaps,
night intensity and color space. Existing texture-budget tests count only
diffuse/emission UIImage values and would miss KVC textures; any such patch
needs explicit accounting of those eight textures. Fewer material batches do
not establish faster GPU rendering when the shader performs more samples.

## Next map discriminator: live building setting

The next local batch modifies `Sources/CityNativeOverlayProbe.swift`, creates
`Sources/CityNativeBuildingSettingProbe.swift`, and modifies
`VisualTests/CityNativeOverlayProbeTests.swift`. App entry, normal MapView,
SceneKit, snapshot backing, camera, pins and navigation remain unchanged.
The existing four-mode experiment remains available. Add one `buildings-off`
mode with no polygon and the same .flat/.automatic/excludingAll configuration.
At both 1450 and 4692 metres, compare none -> buildings-off -> none. Keep the
registered center, heading 20, pitch 35, camera tolerance, two-second settle,
absolute attempt deadline and explicit error captures from the previous probe.

Use a noninteractive UIViewRepresentable host to find the nearest ancestor
subtree containing exactly one public MKMapView. An ambiguous subtree is an
error; do not select the first of several maps. Capture that map's original
showsBuildings value. Entering off mode sets only showsBuildings=false, once
per mode/map identity. Other modes restore the original value. Window removal,
map replacement and dismantle also restore it. Do not replace the map's
configuration, delegate, camera, region, gesture recognizers or credits.
Use normal view lifecycle discovery plus at most one deferred main-loop
attempt, not continuous setting/polling. Later view updates may read the
property without setting it again, so SwiftUI overriding it is visible.

Publish a deduplicated, asynchronous readback with map binding state, original,
requested and actual building flag, plus public configuration/elevation/emphasis.
Readback must refresh after Ready layout; it cannot be only the value returned
immediately after the setter. Include it in each camera JSON. The focused test
`CityMVPVisualTests/CityNativeOverlayProbeTests/testLiveBuildingFlagAndRestore`
requires actual false in off mode and actual original on return. Missing map,
overwritten flag or absent camera readiness produces an error capture within
30 seconds. A false getter is functional evidence only: screenshots must still
prove whether the elevated column disappears while flat footprints, roads,
camera and native credits remain. A negative result is not promoted.

Controller owns project generation, one locked cache, generic build and one
serialized simulator. New runtime work requires at least 10 GiB free. Use a
new bounded evidence directory and closed lifecycle receipt. All existing
dirty work and production boundaries remain in force. Reuse the independent
Goldfish for affected source/evidence review; do not claim a reused context is
a new fresh reviewer.

## Photo-pin continuity repair

The parallel UI maker owns only `Sources/Scene/CityScenePins.swift`,
`Sources/Scene/CityPinRaster.swift` and new `Tests/CityPinTransitionTests.swift`.
The actual landing implementation uses badge spring response 0.46 and damping
0.61, and a local rebound on closing. Before the completed repair below, native
sprang only selection; deselection replaced a 62-point photo with a 42–58-point
photo immediately.

For photo selection-state changes, calculate the previous visible diameter
from the shared raster metrics, multiply by the current local head scale,
and divide by the next raster diameter. Start the new local scale at that
ratio and settle to 1 with response 0.46, damping 0.61 and 0.72-second bounded
duration. Retain raster reveal quantization and visibleScale. Keep glyphs,
texture canvas, anchor, title placement, geographic head.position, camera and
gestures unchanged. Reduce Motion sets scale to 1 immediately. Preserve the
Sendable SpriteKit callbacks and MainActor playback hop that repaired the
earlier runtime crash. Stop playback demand after the action completes.

This provides size continuity, not velocity continuity. Test both 42/58-point
browse endpoints, interruption scales, invalid values and Reduce Motion.
Visual acceptance still needs normal-size motion evidence, including reversal
and release. Compile only after both source writers release their files, using
one frozen source manifest; avoid building while either writer is active.

The controller also creates `VisualTests/CityPinMotionVisualTests.swift`, with
`testPhotoSelectionAndReleaseAtFixedCamera`. It launches the normal registered
district at 1450 metres, closes the selected 101 card, selects its ordinary
photo again and closes it again, retaining mode/distance and capturing states.
The test's native recording can show ordinary release/selection; XCTest's idle
waits mean it does not prove a reversal within 80–160ms. That stronger motion
case remains separate from the deterministic interrupted-size logic tests.

## Verified continuity result and next rendering action

The final continuity run passes six photo tests, three lifecycle-test-double
cases and the normal selection/release flow. A SpriteKit parent-space sizing
bug discovered at runtime is repaired; the tests retain actual rendered-size
checks. A queued-layout fixture issue is repaired without loosening assertions.
The normal application dylib is unchanged across the final fixture-only rebuild.

The live building flag did not maintain false at the first 1450m fixture; do
not integrate it. The first recording run exceeded its artifact estimate and
was aborted, with its failed receipt retained. The final bounded run disables
duplicate automatic video, retains custom captures and passes all ten checks.
See PreviewEvidence/pin-continuity-20261111/verification.md.

Next: isolate SCNMaterial fog affecting the flat native-map snapshot, using
the same far camera and a scoped image comparison. Then correct renderer
ownership so native map text and snapshot text do not blend together. Preserve
authored streets, the native gesture canvas, camera fit and current pin motion.
Increasing white cloud opacity is not an acceptable substitute for that repair.


## Current parallel batch: fog, saved filters and independent checks

The controller remains the Elephant. The reused render maker owns only the
fog-distance change in Scene/CitySceneView.swift and has released it. The reused
UI maker owns only CityMVPRootPages.swift for the demonstrated empty-filter
result. The independent implementation-readiness Goldfish remains read-only;
its reused context is not described as a fresh review. All leaves are forbidden
to redelegate or own builds, devices, caches or publishing. The controller owns
MapSurface's explicit far-camera fixture, its UI test, project generation and
one serialized runtime. These are two bounded slices of existing task342.

The six ongoing product areas are map/3D handoff and Xinyi detail; photo pins;
Saved/globe/Passport navigation; non-map forms and lists; Guide/friends/MCP;
and integration. No single narrow patch establishes completion of all six.
The Guide and permission-based sharing still require executable data contracts
before real network integration. No accounts, friends, endorsements, locations
or model execution are fabricated to fill the preview.

Fog acceptance: at the same registered4692m center, heading20, pitch35, compare
legacy and candidate fog in one binary, separately by day and night. Candidate
starts haze120m beyond the fitted focal plane and retains the950m falloff;
legacy starts at88% of fitted focal distance. A prototype-only explicit
--verify-legacy-fog argument selects the control. The new
--verify-xinyi-far-render path runs only within existing verification auto
launch. Capture readiness, exact camera, viewport, fit error and pin coordinates;
require matched camera and pin positions, then assess the real images. Run the
existing full pinch/rotation/pan/far-return selection test on the candidate.
Native tower removal, duplicate-label ownership and road seams are separate
open failures; clearer fog alone cannot pass those.

Xcode receipt reused: SavvyCityMVP.xcodeproj / SavvyCityMVP scheme, iOS17
minimum, Xcode27.2(27B52), arm64 generic simulator build-for-testing. Direct
xcodebuild fallback; XcodeBuildMCP unavailable and no MCP process owned. The
borrowed simulator is06BE9771-5352-4009-9F51-0BEE7708E7EB on iOS26.5; the
concrete runtime reason is same-camera fog rendering and gesture preservation.
Use the exclusive existing .build cache under3GiB and a192MiB evidence cap,
a screenshots-only task-owned xctestrun copy and a10GiB stop floor. Ignore the
physical iPhone. Release cache/device locks and verify simulator Shutdown before
closing the lifecycle receipt. No signed app, installation, push, Actions,
merge, release or production mutation is part of this local batch.


### Current batch result

Both makers released their files; the controller froze52Swift sources. Generic
arm64 test build and independent bounded source review PASS. Runtime is pending:
the far fixture missed its readiness deadline. Raw logs record the individual
Capture/Passport/Search test PASS(26.885s); the disk floor stopped the following
gesture test after it started, with no completed result. There is no complete
suite or current full-gesture PASS.
The partial result bundle is not readable as a completed xcresult. See
PreviewEvidence/far-fog-20261111/verification.md and its raw logs. The simulator
is Shutdown, locks/capture copy released, and the closed lifecycle receipt is
BLOCKED with zero violations. Resume runtime only above10GiB free or with
explicit acceptance of this exact task's low-space risk; do not clean files.

The next Guide slice can be entirely local: a source-aware brief from the user's
confirmed Place, separating userFacingNote from durableStructuredEvidence,
showing original name/address and saved date (not a verification timestamp),
HTTPS source links, copy address and the existing onOpen map action. It must not
translate, invent live facts, change visit/save state or claim model execution.
Friend sharing follows only after defining an explicit recommendation action
and revocation behavior. A joined-list author label is not verified identity
or endorsement. Existing backend tool-call storage and seeded R8/SLR capability
fixtures do not establish working MCP execution. Exact source pointers are in
GUIDE-AND-FRIENDS.md; this is the next plan, not a delivered feature.


### Next renderer ownership discriminator (not implemented)

A read-only maker proposes a same-binary --verify-native-ground-owner candidate:
skip only the flat labeled snapshot backing, retaining authored ground/streets,
buildings, traffic, camera and pins. Readiness then depends on prepared geometry.
Gate authored street-name decals on scene opacity1 and their entire support
being over truly opaque authored ground, including northern fades and road
reveal holes. Source allowlist would be Scene/CitySceneView.swift,
Scene/CityStreetSurface.swift, Tests/CityTransitionTests.swift and controller
VisualTests/CityMVPVisualTests.swift. Keep the control and backing source; do
not promote or delete on a static argument alone.

Capture identical cameras at5200/4692/4350/4150/3650/2900/1450m and lateral pans
across north/east boundaries. Require readable roads, no doubled text, native
credits, unchanged camera and selected-pin behavior. The strongest failure is
the native101column exposed beyond authored ground or native text clipped at a
coverage edge. Either blocks promotion. This differs from removing authored
ground, which previously lost street detail. Fog and label ownership do not
prove native-column removal. Runtime is currently blocked by disk space, so no
new renderer experiment or street expansion has begun.


### R2 resource recovery and verified result

The user explicitly approved one bounded retry at9.2GiB with8GiB stop and128MiB
evidence. The generic build and revised direct Ready query pass. R2's completed
result records2/2tests: matched day/night far comparison75.477s and the full
selected-pin pinch/rotation/pan/far/manual-return flow118.899s. All52sources
match the R2 manifest, and its application dylib matches R1. R1's individual
Capture/Passport/Search PASS remains same-app evidence, not a relabeled suite.
See PreviewEvidence/far-fog-r2-20261111/index.html and verification.md. Runtime
minimum was8.458GiB; no resource stop, no arbitrary-file cleanup. The borrowed
simulator is Shutdown and capture copy/locks are removed. The R2 lifecycle
receipt is closedPASS with zero violations. Independent final evidence review
also passes this bounded scope. The user's cleanup recovered free space above20GiB.

Observed result: the candidate clears focal linework but duplicated labels
remain; fog is only a bounded improvement. Before a full ground-alpha/mip
ownership gate, isolate one variable: omit only the broad snapshot backing in
an explicit verification candidate, retaining every authored ground/road/name,
building, tree, car, camera and pin. This can identify whether removing the
second labeled image improves the seam. It cannot yet approve all authored
label coverage or native-column removal. The exact whole-support alpha gate
also needs a conservative GPU mip-filter footprint; one-pixel or corner-only
sampling would make an unsupported opacity claim. Do not introduce that
unproven predicate merely to make tests pass.


## Snapshot-removal discriminator (not a default change)

The render maker owns only Scene/CitySceneView.swift and has released it. Its
immutable --verify-native-ground-owner process flag skips snapshot preparation,
marks the backing prerequisite ready once, and permits authored rendering/pins
without backing. Default launch is the verified R2 control. No roads, names,
model geometry, fog, pin math or camera are edited by the maker.

Controller owns Sources/CityMVPMapSurface.swift's verification-only distance
allowlist and VisualTests/CityNativeGroundVisualTests.swift. Explicit far-render
launch can request5200/4692/4350/4150/3650/2900/1450m. Readiness retains geometry
and exact requested distance; at5200prewarm boundary projection may intentionally
be absent. Every inside-prewarm case still requires valid projection and fit.
Two paired tests compare all seven distances by day, plus1450at night, always
same registered center, heading20 and pitch35. Keep the45second Ready deadline
and equal2second settle. Capture cameraJSON and images before assertions;
compare actual selected identity, single semantic pin, actual pin-frame bounds,
latitude/longitude, distance, heading, pitch and393x852viewport across each pair.
All model/road/label losses and exposed columns must be assessed in real images,
not inferred from functional PASS. No unproven alpha/mip ownership gate is added.

Controller also extracts the existing full native-gesture method into one
private helper, retaining every assertion. The existing test calls it with no
new arguments; testNativeGroundPinchKeepsLandmarkSelectedAcrossDistrict passes
only the native-ground flag. This must prove actual select/pinch/rotation/pan/
far/manual-return behavior for the candidate, without changing input/assertions.

New evidence directory: PreviewEvidence/native-ground-20261111, capped256MiB;
cache remains exclusively locked and capped3GiB, one existing borrowed simulator,
screenshots-only capture copy,10GiB default stop. The prior8GiB risk approval
was scoped to R2 and is not extended; current free space has recovered above20GiB.
No source owner may build, run a device or publish. The controller generates the
local project, freezes sources, compiles, runs and releases all resources.
Promotion requires independent source and actual-image review. If the native
column or road seam is worse, keep the normal control and record the negative
result. Production, phone, credentials, Actions and GitHub state stay outside.


### Snapshot-removal result: not promoted

See PreviewEvidence/native-ground-20261111/index.html and verification.md.
Build and bounded independent source review pass; the completed runtime result
is1PASS/2FAIL, exit65. The paired3650/2900/1450day and1450night case passes with
matched cameras and semantic selection frames. The candidate's physical first
pin selection fails; the far case fails in the first5200CONTROLlaunch because
registration was unavailable, so the remaining far poses are untested. Do not
infer a no-event tap or SDK throttling from those observations. Actual images
retain near/night authored streets and pins, but3650building alpha ghosting
remains. The independent reviewer accepts these negative findings/provenance,
not default promotion. All53sources are retained under source-snapshot and
match the manifest. The resource receipt is closedTASK_FAILED with zero
violations; minimum free17.503GiB, no stop, simulatorShutdown, copy/locks gone.
Normal launch remains the verified R2 rendering path.

Next source work needs bounded pin-routing diagnostics (no guessed behavior
fix) and a fixture that reuses one registration per renderer process while
stepping through all distances. Preserve the original failures. Never use an
invented geographic offset to make the fixture render. The existing uniform
model-opacity fade is a separate source of translucent3650building overlap;
snapshot removal alone cannot solve it. A future opaque/cloud reveal design
must keep camera continuity and current photo-pin ownership, and needs actual
motion evidence before promotion.

### Dock interruption verifier: next evidence plan, not implemented

The actual shared callback is ContentView.selectRootTab(_:), also used by the
CityMVP dock. Future scope: prototype-only guarded addition in ContentView,
new Sources/CityMVPDockBurstProbe.swift and
VisualTests/CityDockBurstVisualTests.swift; leave BottomBar/Map/Scene unchanged.
Use existing --verify-xinyi --verify-xinyi-auto --verify-xinyi-selected for the
1450m selected starting state; do not invent an unsupported distance flag.
The explicit probe starts one MainActor task using absolute deadlines:
Saved0ms -> Passport80ms -> Saved160ms -> Map240ms. Call selectRootTab, not a
separate selection setter. Record actual dispatch times and fail the attempted
interruption if lateness>40ms or intervals<40ms; completion after800ms records
finaltab/path/drawer/cover. Require unchanged camera, selectedidentity/count,
pin frame within2pt and inactive pages absent fromAX. Record a short original-
speed movie separately from time traces. Cover normal, ReduceMotion and
ReduceTransparency. This proves programmatic real-state render interruption,
not native80ms touch latency or GPU FPS. Native dock tap/drag stays separately
covered. Verify the local build's actual compilation flags before choosing a
DEBUG guard; the SAVVY_CITY_MVP guard and explicit launch argument are mandatory.


## Pin-input diagnosis and reduced-registration R2

Only five sources change from the retained53-source negative experiment:
Scene/CityPinControl.swift (render maker), Sources/CityMVPMapSurface.swift and
VisualTests/CityNativeGroundVisualTests.swift (UI maker),
Scene/CityDistrictRegistration.swift and VisualTests/CityMVPVisualTests.swift
(controller). Both makers have frozen/released their files. Normal renderer
selection still defaults to the R2 snapshot control; no candidate promotion.

New pin diagnostics require both --verify-xinyi and --verify-pin-input. Separate
32lifecycle/96event budgets prevent layout chatter from consuming tap evidence.
Log only public object identities/booleans/coordinates: cached/fresh/hit map,
last-layout window.hitTest, converted host bounds, recognizer attachment/state,
shouldReceive reasons, recognized entry/hit/miss/footer and dispatch. No private
UIKit class names, user content, AX getter/activation override or rebinding fix.
Last-layout hit testing is explicitly not a tap-time observation. Instrumentation
may perturb timing; its passing tap alone cannot establish a functional repair.

The explicit render fixture now has a camera Menu/state override. Each paired
method uses just onecontrol and onecandidate process, realMenu actions and the
same camera whitelist,45second deadline includingMenu andReady,2secondsettle,
post-settle actual registration/center/angles/fit/pinidentity/frame checks.
Night1450uses the existing lighting toggle, without another registration.
Failure captures raw available fixtureJSON plus screenshot before throwing.
No retry, fake offset or swallowed failure is added.

Registration diagnostics record public error domain/code or resultcount/match,
and deadline/task cancellation. Only Sendable scalars cross toMainActor for
logging; the original search match/finish/cancel race is retained. The new
physical-input diagnostic case uses the original full gesture helper, with
before-tap frame/hittable/screenshot capture only under the diagnostic flag.
The original control and uninstrumented candidate keep their event timings;
failed selection now retains a custom failure screenshot before the same assert.

Controller owns one existing locked cache and borrowed simulator. New evidence
PreviewEvidence/native-ground-input-r2-20261111 is capped256MiB; cache cap3GiB,
default10GiB floor, screenshots-only capture. Runtime monitor may retain only
the public landmark trace for each verified task appPID, with no user content.
Generic build must pass before the three focused cases. Resource shutdown and
independent evidence review remain required. No phone/GitHub/Actions/production.


### Input R2 recovered closeout and next correction

The interrupted observation was resumed through its original process handle;
the handle was absent, and authoritative process/runtime receipts established
it had terminated. Do not restart that run. Its readable completed bundle
records instrumented gesturePASS129.672s, night fixtureFAIL129.467s and handoff
canceled after its initial5200controlcapture. The resource monitor hit temporary
259.015MiB against256MiB and exited75; retained output shrank after finalization.
The historical stop remains recorded. SimulatorShutdown, no owned processes,
copy/ownerlocks released; receiptTASK_FAILED,0lifecycleviolations. Exact53sources
and all public PID traces are retained in
PreviewEvidence/native-ground-input-r2-20261111. Instrumented firsttap has a
confirmed allowed/hit/dispatch chain, but no functional repair was made.

Night failure has a deterministic fixture defect: -cityMVP.night NO is a
UserDefaults argument-domain override, which outranks subsequent app writes.
Apple's primary documentation is
https://developer.apple.com/documentation/foundation/userdefaults . The target
app's persistent night value after the run istrue while its fixture readsfalse;
there was no pre-tap persistent read, so this alone does not prove the tap write.

Correction scope is only CityMVPApp.swift and CityNativeGroundVisualTests.swift.
A static prototype-only bootstrap, requiring --verify-xinyi AND
--verify-start-day, seeds the day preference exactly once per process. Normal
launch does not seed it. The paired fixture assigns a fresh argument array with
that one-shot flag, omitting the forced key. Real lighting-button toggle and all
post-read assertions remain. No binding, palette or action is rewritten.

Next verification uses the existing uninstrumented candidate full-gesture case
plus the two sequential comparison cases. Run each as a separate completed
result bundle, serially under one existing cache/device lease, to finalize and
discard system attachments between cases. The256MiB total evidence cap and
10GiB stop floor remain. This is a new discriminating check: diagnostic overhead
is absent and night initialization is no longer a forced override. The prior
failures are retained; no wait/assertion/camera has been weakened. Candidate
promotion and whole-app fidelity are still not approved.

### Solid-surface candidate and isolated renderer proof

R3/R4 stopped from a monitor counting sparse compiler-cache logical sizes.
R5 retained the actual sparse-file/allocated-block evidence, passed the build,
then failed all three live-map checks before intended interaction/visual
acceptance. Public registration error is NSURLErrorDomain -1001; the handoff
sample also shows a CoreLocation startup wait. The failed task and the harness
EPERM during finalization remain recorded; resources were closed without retry.

The controller added an explicit --verify-opaque-reveal candidate: a shared
screen field discards outside geometry while preserving authored opacity inside;
SpriteKit clouds cover the same cut below photo/title sprites. Geometry/material
copies protect cached originals, and existing fragment transparency is retained.
Normal launch keeps the prior renderer. The paired live-map test holds native
ground ownership constant and varies only the opaque flag; it is compiled but
has not run. Camera/pin math was not changed.

PreviewEvidence/opaque-reveal-probe-20261111 contains twelve passing macOS Metal
pixel checks and the passing iOS synthetic-camera district fixture. R2 records
applied35/70/100day and100night, actual393x646viewport and unchanged projected
photo position, with55source hashes and original10.593second recording. The
fixture bypasses location/search and cannot establish geographic registration,
native-column suppression, map gesture anchoring or frame rate. A reused
independent read-only reviewer checked the new source and rendered frames;
the separate readiness lane returned Bad Request, not a verdict. Visual default
promotion is rejected: the closed white cloud band looks like a portal and
clipped arcs. Next change must make cloud coverage organic while preserving
opaque interiors and shared cut coordinates. No phone/GitHub/Actions/production
change. Lifecycle closedPASS for the bounded renderer proof,0violations; device
Shutdown and ownerlocks released. Whole-app/Anywhere acceptance remains open.


### Material-tone batch result and final building-setting discriminator

The organic cloud-cut candidate remains unpromoted:35%still cuts101 and reads
as an aperture. The controller added an explicitly gated material-tone mode:
full solid geometry, neutral-to-authored elevated albedo, sparse wisps, unchanged
main camera/photo math. A reused independent checker identified the actual
road/night atlas at0.87/0.89m inside the original0.8m ramp; it now begins1.5m,
and the Metal fixture covers those heights plus0/1/1.5.28checks pass.

Both synthetic modes use identical35pitch/20heading/1450distance. Each six-frame
35/70/100day/nightcase passes with57unchanged source snapshots; the original
candidate movie and local gallery are underPreviewEvidence/material-tone-20261111.
Independent review confirms full101/spire and no aperture at35; wisps are barely
visible. This is bounded visual improvement, not reference-quality cloud thinning.

The final legacy-mapType diagnostic fails4false-readback assertions at1450/4692:
mapType0/configwrites0/maptypewrites1;falseignoredimmediately, actualtrue, full
renders1/2. Together withmodernUIKitfailure, stop showsBuildings variants.

Real native comparison builds successfully and captures registeredcontrol4692/
3650/1450day+1450night. Candidate secondlaunch search then failsNSURLErrorDomain
-1005(connectionlost), staysglobe/fitError-1/readyfalse; no candidateframe or
physicalinputpass. Exact57sources, rawfailureJSON/screenshot andpublictasktrace
retained. No retry/fallback or assertion weakening. Default remains unchanged.
A source-reviewed additive test checks actualmaterialTone/opaqueReveal metadata.

This local batch does not change authored building details, ship/phone/GitHub/
Actions or production. Reused independent review is not a fresh Goldfish round.
The384MiB evidence/3GiBcache lifecycle must close with deviceShutdown and locks
released; failed native acceptance is preserved instead of relabeledPASS.


### Same-run native anchor, real input and boundary results

Previous goal turn is progress, not completion: material-tone renderer proof
passed; candidate live-search startup then failed-1005. This turn adds a strictly
verification-only paired anchor, gated by --verify-xinyi AND --verify-xinyi-far-render.
Only an actual live-search control from THIS test supplies the candidate input.
Exactly one nearby finite coordinate pair is required; invalid/duplicate input
returnsnil. No persistence, historicalfixture, normalstartup cache orfallback.
Provenance and actual anchor are part ofrawmetadata. Three new safety/roundtrip
units plusprovider andtimeout/cancellation cases pass7/7. Their inputs remain
unchanged after additive selectedpoint metadata/visualtests.

Real pairPASS:4692/3650/1450day and1450night; selectedidentity/title, camera,
anchor andsemanticphoto frame agree. Night nativepinch1450→2081, rotation20→336,
freepan andpinch-in1432pass actualcamera/fit andselectedcontact assertions.
Second pairPASS:5200/4692/4350/4150 andphysicalpinches5789→3897→5675 across
prewarm, same selectedplace retained. Each runtime has57unchanged inputs and
source snapshot. Original near20.07s/handoff16.61smovies andsampleprovenance retained in
PreviewEvidence/paired-anchor-20261111. This is not all-frame stability orphone
proof. CurrentCoreDeviceinventory lists no physicaliPhone.

Independent source review accepts gating/provenance andpreservedassertions.
Actualnearframe review accepts opaqueimprovement at3650but rejectsdefault
promotion: ground remains tanrectangularplate/straightnorthfeather; native101
column remains at5200 andwholeauthoreddistrict enters/leavesbelowprojectiongate.
Numerical/inputPASS doesnot prove visualcontinuity. Next correction is a
continuous appearance gate that reacheszeroBEFORE projection is removed,
without restoring transparentnearbuildings, plusgroundpalette/boundarymatching.
Keep actualcamera/pin math andno further showsBuildings experiments.

CurrentshipInk/design/accountdata, phoneinstallation,GitHub/Actions unchanged.
The controller exclusively owns the existingcache/device lease untilclosed;
nodevice/writer runs aftercloseout. OverallAnywhere90%goal remainsactive.


### Shared ground coverage and photo-owner continuity

The isolated ground candidate now uses one real-feature coverage image across
base/roads/civic/shadow atlases. The first5ground tests failed and are retained;
bitmaporientation, explicitdestinationIn drawing and the isolatedtest camera
were repaired without weakening assertions. The unchanged5tests thenPASS.
Black/white core-material renders agree in day/night; unknown controls differ255.
This does not prove MapKit layerordering. Nightlightatlas remainsunchanged.

All8pin+3arrival testsPASS. Fresh selectedphoto mounts no longer replay the
browse-to-selected spring; actual selection/release/interruption remains.
Real native nearpairPASS with20.228333smovie. The first handoff processreturned0
butexecuted0tests: notPASS. Exactenumeratedselector including() thenexecutes1PASS
with17.5smovie and58unchangedinputs. Nine sampledcyanrims are184pxwide, versus
prior106pxshrink. Caption disappears in nativefallback; controller adds only
visibleTitle using sharedbounds, gatedby selected&&!rendererOwnsPins. Caption
buildPASS; freshcaptionhandoffrun stoppedatevidencecap fromXCTestAXlogging. Incompleteresult, notPASS. Visiblecaptionnotyetaccepted; donotrepeat unchangedloggingconfiguration.

Reused independent review sees reducedrectangle but rejectsdefaultpromotion:
irregularnativegaps, clippedPOIs, abruptroadends, graycontrast andnative101
geometry persist. Arrivalintermediateframes insufficientforvisualacceptance.
Defaultground/arrivalroute remainsunchanged. Source/daynight/camera/data/privacy
boundaries remaininforce; noGitHub/Actions/phone/signing/productionaction.
Currentgallery/results:PreviewEvidence/owned-ground-pin-20261111/.


### Visible caption acceptance and next renderer defect

The new single-live-registration caption test builds and runs1actualPASS,
58inputsunchanged. Existingpairedtests remainintact; onlythe helper's provenance
parameter is addedwithpaired-fixturedefault. Actualrecords5789native→3897scene
(fit.0383)→5675native; finalnight5675. Independentpixelreview confirmsfullsize
photo+visiblecaption acrossbothowners/daynight inoriginals and03/06/12/18samples.
Currentgallery:PreviewEvidence/caption-bounded-20261112/index.html.

Thefullpairedcaption attemptstillcanceledattransient128MiBAXloggingcap;
collect-test-diagnosticsneverdoesnotprevent in-progresslogging. Keepthatfailure.
Focusedtestdoesnotclaimallframeanchor/FPS. At06sgeometryisstilltranslucent and
nativePOI/roads showthrough. Nextcandidate mustpreserveopaquesurfaces during
appearance; cloud/coveragecanrevealthemesh butnodeopacitycannotproduceghosts.
No native-ground/arrivaldefaultpromotion, phone,GitHub,Actions orproduction.


### Pixel-discard arrival experiment rejected; opaque cloud handoff remains open

Candidateusedfixedscreenpixelcoverageinsteadglobalopacity.23Metal+22independent
PNGchecksPASSafterraw8bitoracle repair; calibratedNSColorconversion caused the
initialfalsefailuresandallresultsare retained. Actual5000nativeimagefit.02978
showsdustlikestipple andnativePOIreadablethroughholes. Reusedindependentreviewer
rejectsvisualpromotion. Binarycoverage preservesperceptualdouble-map; donotrevive
itmerelybecausepixels/testsPASS.

R1–R3readiness45s waitsFAIL; rawposttimeoutstateisready. R4usesexistinginitial
camera menu, thenunchangednumeric/selection/gesture assertions:1actualPASS with
58unchangedinputs and18.433333smovie. Itisstillarejectedvisualcandidate.
Allfourcanonicalcandidatefiles restoredexactbaseline; final58inputs matchprior
captionproof. Source/diff/results preservedinPreviewEvidence/solid-arrival-20261112.
NoApp/phone/GitHub/Actionsproductionpromotion. Nextdiscriminator:prewarmandshow
opaque101silhouetteearlier, withcoherentgeographiccloudbankscoveringhandoff;
noportalclip, nofulldistrictglass, nopixelstipple. Nativecredits/POIs stayuseful.


### Geographic cloud handoff: functional repair, visual rejection

The explicit cloud-handoff experiment now passes 41 unit/GPU tests and one
native UI test against the same 60 source inputs. A transient MapProxy failure
outside model preparation lost native pin/cloud coordinates; the existing
single layout refresh now also handles this case. The ten captured samples
retain selected identity and valid positions; three real pinch checkpoints
cross the ownership boundary. This is checkpoint evidence, not every-frame
stability or smoothness.

The white boundary banks remain visually rejected and unpromoted. Offscreen
SpriteKit/UIKit blend comparison and an unused SceneKit-plane alternative both
failed; they are frozen in evidence and restored out of canonical source.
Current sources exactly match the passing R3 run. Next: isolate transparent
compositing before changing appearance again. See
`PreviewEvidence/cloud-banks-20261112/RESULT.md` for original images, the 16.94s
recording, failed attempts and proof boundaries. No phone, PR, Actions or
production changes. Overall Anywhere acceptance remains open.


### Transparent cloud compositing: daytime repair retained

A single transparent cloud reproduced clipped white output before overlap.
Camera-local quads plus a public linear-color/display-alpha pass now match
UIKit composition within2/255 at all60 sampled day/night comparisons.
The62 recorded current inputs match43 passing unit/GPU tests and one passing
native UI run, including three pinches and repeated night poses. Actual5000/8500
day images show soft clouds with clear photos/titles. Night1450 retains lights
and building details. Night8000 still has no visible clouds, including after
additional redraw; its producer count/opacity is not pixel proof.

Retain the daytime repair behind the four existing verification flags; do not
promote the default or claim full transition/Anywhere acceptance. Next inspect
producer patch axes versus actual consumer nodes/frustum/material/fog.
The geometry leaf also established that the current building extract ends at
about1.326x1.224km; opening radius gates adds only2 buildings. One bounded
context-data request timed out without headers/body, so no new geometry was
integrated. Source/evidence/results are in
`PreviewEvidence/transparent-blend-20261112/RESULT.md`.


### Night cloud repair and outer context experiment

Night banks now render after the camera-local cloud-plane depth2→8 repair;
44unit/GPU checks and full native1UI retain62inputs. Independent reused check
accepts the scoped source/functionality, but the recording exceeded128MiB, so
that prior receipt remainsLEAKED/fail despite XCTestPASS. All resources closed.

The public3x3km planned42-cell footprint query yielded7602ways/all542heroIDs.
Explicit --verify-context-ring adds6434 neutral outer volumes in83 merged chunks
without expanding ground/roads or adding facade textures/POIs/user truth. Two
review findings—raised minimum-level data loss and invalid crossing/backtracking
rings—were fixed. Final48unit/GPU+affected1UI day/nightPASS on68unchanged inputs;
prior full gesture case belongs to the earlier source and is not finalfullsuite.
Comparison/evidence/limits:PreviewEvidence/context-ring-render-20261112/.

Normal default remains unpromoted. Gray-to-authored boundary, native label
occlusion/leakage, far native101column/arrival continuity,26/24facade budget,
rapid interrupted dock/a11y proof and real Guide/friends/MCP remain open. No
phone/signing/GitHub/Actions/production action. Overall90% goal remains active.


### Native POI overlap and facade-budget repair

Current70-input source passes61unit/GPU/preparation checks and one paired native
UIcase. Static --verify-quiet-native-labels uses publicflat/muted/excludingAll;
same-runactualMapKitanchor and9field/pin comparisons agree exactly. Realnear
pinch/rotate/pan/return checkpoints pass; original26.51smovie is bounded anddoes
notcoverfinalreturnsettle. Actualimagesretainphotos/captions/lights andremove
nativePOIleakage. Finalnear/outside-district POIpolicy/defaultpromotion remainsopen.

Theworker'sretailmergefirstfailedGPUoracle(variantcarrier/nightUV); bothcauses
werefixedwithrealopaqueimageUV1 andexplicitlightscale. Unchanged12GPUcomparison
pairs×4variants pass; all8originaltexturesareaccounted. Actualbudget24batches/
24materials/94.8MiBbackingimages nowpassesunchangedbounds; historical26/24no
longerdescribescurrentcode. NoFPS/totalGPUmemoryclaim. RetainfailedR1evidence.

Greyboundary/roadseams/roofshimmer/far101column/arrival/defaultintegration,
interruptednav/a11y andrealGuide/friends/MCP stillpreventoverall90%acceptance.
Evidence:PreviewEvidence/native-labels-20261112/. Localonly; no phone/GitHub/
Actions/signing/production change. Existingreusedchecker isnotfreshGoldfish.


### District-scoped label policy and next label data

Final R2 passes 65 units/GPU/preparation checks and two native UI flows on the
same 72 inputs. Center/east/return/physical-pan policy revisions are 1–5 with
zero camera displacement from each setting change. Day/night stays at revision
1. Initial native verification exposed both an inappropriate scene-pin-ready
requirement outside the viewport and a real projection-gap reversal; the
verifier correction and state repair are retained with the failed evidence.

Native POIs restore outside the core, but gray context geometry still occludes
some text. This remains a flagged experiment, with no whole-map/default/90%
acceptance. The offline inventory found 3,241 prospective outer identities,
1,001 with source English names, in existing verified public data. Next label
work can paint context names above the scene with bounded collision/identity
handling; do not invent translations, merge same-name businesses or write Map
Stamps automatically. Inventory is not yet integrated. Evidence and source
limits: PreviewEvidence/district-labels-20261112/.

Other goal gaps remain: gray/style/road/roof boundaries, far 101 and continuous
arrival, a tested normal City Lab preview route, interrupted dock/a11y proof
and actual Guide/friends/MCP services. Production, phone, GitHub and Actions
remain untouched. The active overall goal has not passed its completion audit.
