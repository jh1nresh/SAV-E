# Savvy main map: Xinyi district

This directory now supplies the authored map, neutral three-destination shell
and private Guide/Friends UI used by the main `com.wanderly.app` target.
Use `SAV-E.xcodeproj`, scheme `SAV-E`; do not build or deliver a standalone
City Lab app. Historical target names and prior evidence below are retained
for provenance and do not prove the current main build is installed or verified.
The main account gate, production persistence and Share Extension/App Clip
handoffs remain in the main project. Earlier unlocated saves/visits remain
available through the account-filtered, read-only Place history surface.

Future regions follow [the region blueprint](REGION-BLUEPRINT.md), using
`SavvyMapRegion` profiles and the same camera, geographic pin, cloud and
asset-provenance rules. Shanghai remains an explicit missing-key/SDK placeholder.

Choose **Taipei** and pinch into the district. The 3D scene follows the
Apple Maps camera and dissolves back to the basemap when zooming out. Geometry
is assembled in cooperative batches and installed only after resource preparation;
the native map remains available in the meantime. A failed preparation exposes
an explicit Retry action. Landmark alignment also has a ten-second deadline and a manual Retry control; a missing lookup never substitutes guessed coordinates. Leaving and returning to the district reuses the scene
while this map screen remains mounted. Use
**Explore** to jump to the City Hall Road and Songzhi Road intersections.
The two blocks include illustrative storefronts, sidewalk and road details,
and simulated cars. The northern corridor includes City Hall, public squares,
planted parks and raised retail walkways based on the bundled public footprints. The original 101 model has eight flared, chamfered tiers and a stepped crown; camera containment reads those same profiles. Roof trim and bounded rooftop equipment follow eligible building footprints and avoid the tower shaft. Traffic is animated only at close zoom, while the app
is active and Reduce Motion is off. Taipei 101 and ATT 4 FUN have distinct
photo pins. Thin photo rims and compact labels distinguish ordinary context
pins from the cyan selected badge; only a saved place receives a bookmark. The Shanghai row is a configuration placeholder; no Amap SDK
is connected.

## Historical prototype verification

Ordinary City Lab launches now use the integrated native-ground/cloud/context
renderer without verification flags. Explicit historical verification arguments
and `--citylab-legacy-renderer` retain comparison behavior. A pending3D
preparation shows a nonblocking status pill.

Current96 focused unit/GPU/preparation checks and the strict inspected native
camera/pin/tab/night flow pass. The separate noargs full journey also passes
with unchanged app inputs. Development build16 was signed, installed and
read back on the connected iPhone, then opened to the101 day demo; the separate
Savvy143 app remained unchanged during that batch. The user then authorized
updating the existing Savvy phone app to144; the same verified preview code is
installed there, with the original vault checked byte-for-byte after launch.
This is a local phone preview, not a store release. See [results and limits](PreviewEvidence/preview-route-20261112/RESULT.md).
The prior [label preview](PreviewEvidence/context-labels-20261112/comparison.html)
shows the sourced-label/CJK repair. These are scoped local/device results,
not whole-map fidelity, every-frame/FPS or release acceptance.

Earlier local verification follows for context.

The latest native-label/facade batch passes61 focused unit/GPU/preparation
checks and one paired native UI test on70 unchanged inputs. The explicit
--verify-quiet-native-labels candidate removes overlapping native POIs and
reduces basemap-label emphasis while preserving authored pins and lighting.
Actual pinch/rotate/pan/return checkpoints pass. Retail variants now share one
material with all8 original textures; final full-district budget is24 batches
and94.8MiB backing images, within the existing limits. The initial GPU failure
was retained and repaired, not hidden by a looser tolerance. See the
[current comparison and recording](PreviewEvidence/native-labels-20261112/comparison.html)
and [results/limits](PreviewEvidence/native-labels-20261112/RESULT.md).
This remains an explicit local label experiment; default/outside-district POI
policy and full Anywhere fidelity are not accepted.

Earlier local verification follows for context.

The 2026-11-12 cloud repair now retains soft day clouds and restores the
previously missing night banks. A translated-camera GPU regression failed
at the old cloud-plane depth and passes at the corrected depth. All44 focused
unit/GPU checks and the full native-map UI case pass against62 unchanged inputs;
selected-photo identity,2pt checkpoint anchors and three real pinches retain
the existing assertions. Independent source/functional review passes within
this experiment. The final recording exceeded the128MiB evidence cap, so that
run's resource receipt is LEAKED despite XCTest PASS; no simulator, process or
ownerlock remains. This is not a full transition/default/Anywhere acceptance.

The outer3x3km public footprint query is complete:7602 building ways, including
all542 hero IDs. The separate --verify-context-ring experiment now passes48 focused unit/GPU
checks and one affected day/night native UI case on68 unchanged inputs. It adds
6434 untextured outer buildings in83 chunks without extending ground or roads.
See [current comparison](PreviewEvidence/context-ring-render-20261112/comparison.html)
and [verification limits](PreviewEvidence/context-ring-render-20261112/RESULT.md).
The default renderer remains unchanged. Earlier before/after evidence is in
[daytime comparison](PreviewEvidence/transparent-blend-20261112/comparison.html).

Earlier local batches follow for context.

An earlier local batch fixes selected-photo remount shrink and introduces an
explicit real-feature ground-coverage experiment. Eight pin tests and three
arrival tests pass; all five ground tests pass after retaining and repairing
the first failed run. Same-run MapKit comparisons pass at4692/1450day and
1450night with native gestures. A separate boundary test passes5200/4692/4150
plus pinches outside and back. Its original17.5s movie shows a full-size photo
across ownership changes; nine sampled rims remain184px wide. It also exposed
an absent native-fallback caption. Its repair builds and passes source review;
the full recording stopped at the diagnostic-storage cap. A subsequent
single-registration focused test passes with58 unchanged sources, and original
day/night images plus four movie samples confirm a full-size photo and visible
caption across ownership. See`PreviewEvidence/caption-bounded-20261112/index.html`.
Intermediate arrival still shows translucent geometry; the overall handoff
remains unaccepted.

The broad tan rectangle is reduced, but native openings/labels, road endings,
gray building contrast and far native101geometry still expose the composite.
Ground/arrival candidates remain verification-only; normal launch is not
promoted. These tests do not establish all-frame attachment, FPS, phone proof
or90% similarity. The local gallery and exact results, including a zero-test
invocation that is explicitly notPASS, are in
`PreviewEvidence/owned-ground-pin-20261111/index.html` and `verification.md`.
Previous comparisons remain in`PreviewEvidence/paired-anchor-20261111/`.
All shared-anchor tests use only the actual same-run control lookup; ordinary
startup still uses live search. No further showsBuildings flag variants are
planned after modern and legacy probes ignored the setting.

The latest local integration on 2026-11-11 passes the generic arm64 test build,
Capture draft/Passport information flow, and the retained-map sliding dock test.
The pin-selection actor-isolation crash is repaired on both tested entry paths.
The corrected native test now passes selection, pinch, rotation, pan, card/dock
clearance, return to the native map and a manual pan back to the same selected
marker. Ten layout tests also pass. The card relocates independently before
moving navigation; physical map touches remain on MapKit's original canvas.
The facade budget test remains open (26 material batches against a limit of24),
and the far map still looks washed out with overlapping labels. These results
do not establish whole-app readiness or90% visual similarity.

The subsequent native-only overlay probe passes its generic build and three
focused UI tests, including the normal-launch dock regression. Eight captures
show that the tested polygon overlays retain the native 101 column and add a
gray ground shape, so that approach is not promoted into the normal renderer.
The probe is available only through `--verify-native-overlay-probe`.
See `PreviewEvidence/native-overlay-20261111/verification.md` and the six
[workstreams](WORKSTREAMS.md) for the current owners, scope and remaining work.

The photo-pin continuity revision passes ten focused checks: six actual-size
transition cases, three adapter lifecycle cases using an explicit test double,
and normal-app selection/release. Photos keep their intrinsic canvas while
retargeting with the landing's spring parameters. The genuine live building
flag experiment did not maintain the requested false value and is not adopted.
See `PreviewEvidence/pin-continuity-20261111/verification.md` for the current
hashes, movie provenance, retained failures and remaining visual/runtime gaps.

Evidence for this local diff is in
`PreviewEvidence/selection-input-r2-20261111/` and
`PreviewEvidence/selection-verify-20261111/`. The latter has the final source
hashes, unchanged application-binary receipts and corrected native test. Earlier
Capture evidence is in `PreviewEvidence/explicit-motion-20261111/`. The UI uses the Ramin reference on
non-map surfaces while retaining the map dock's lens and glow; accepted product
direction and reference boundaries are in [Guide and friends](GUIDE-AND-FRIENDS.md).

Source-derived desktop checks cover the district geometry, sampled camera/pin
projection, cloud clearing, day/night palette, navigation dock and place card.
These checks do not establish current physical-device gesture continuity, frame
rate, contextual-pin overlap or whole-app similarity to Anywhere. A fresh phone
installation and runtime check remain separate gates. GitHub Actions stays disabled.

## Run locally

Use an Apple silicon Mac with Xcode, XcodeGen, Python 3 and PyYAML. Verified
with Xcode27.2 and an iOS26.5 simulator. The separate target now compiles a
Metal shader; the matching Xcode Metal Toolchain component is required.
Inspect it with `xcodebuild -showComponent MetalToolchain -json`; if missing,
install the matching component with `xcodebuild -downloadComponent MetalToolchain`.
Run from the repository root:

```sh
python3 Prototypes/CityMVP/run-bounded.py bash Prototypes/CityMVP/build-local.sh
xcrun simctl list devices available
```

Choose a shutdown simulator from that list. The runtime check requires
at least 10 GiB free at startup.

```sh
export SAVVY_CITY_MVP_DEVICE='<simulator-udid>'
python3 Prototypes/CityMVP/runtime-local.py --xinyi-only
```

The verifier takes an exclusive lock on its simulator and build cache. It
builds and runs the hosted and focused UI tests, then launches the app for
inspection. From another shell, request closeout with
`touch Prototypes/CityMVP/runtime-stop.local`. The verifier shuts down its
simulator and releases its locks. It does not delete the simulator or cache.

## Assets

[The Taipei extract](Resources/taipei-osm.json) is ©
[OpenStreetMap contributors](https://www.openstreetmap.org/copyright) and is
distributed under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
The asset has its own license, separate from the app code. Scene geometry and
store names are illustrative and do not represent current conditions.
See [photo credits](Resources/PhotoCredits.txt) for image sources, licenses
and crop disclosures.


### Latest local fog and gesture verification

See [paired captures](PreviewEvidence/far-fog-r2-20261111/index.html) and
[verification limits](PreviewEvidence/far-fog-r2-20261111/verification.md).
The current generic test build and two focused UI cases pass: exact day/night
fog cameras and the complete selected-pin native gesture flow. This does not
approve renderer seams, the native101column, whole-app fidelity or a phone
release. Snapshot/native text duplication remains the next rendering problem.
