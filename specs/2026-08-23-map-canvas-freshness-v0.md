# Map Canvas Freshness v0

- Paid user job / observed failure: The map is the surface where a user decides
  "where do I go from what I saved". Founder review of the live map against
  Apple Maps found it reads heavy and dead: no color hierarchy, no depth, and
  every saved place shouting at equal weight. A user cannot scan 73 Map Stamps
  and pick one. Root cause is not a single style choice — four independent
  greying layers were stacked and multiplied in `MapView.swift:95-119`
  (`emphasis: .muted` + `.saturation(0.78)` + `.contrast(0.96)` + a
  `AtlasPalette.canvas.opacity(0.06)` scrim), plus opaque chrome on all four
  edges that frames the map as a rectangle instead of a canvas.

- Acceptance criteria:
  - **A1 (landed, verify only).** Basemap carries exactly one tint decision.
    `emphasis: .automatic`, no `.saturation`, no `.contrast`, no canvas scrim.
    Parks, water, and retail districts are visually distinguishable from each
    other at default zoom.
  - **A2.** Map chrome is floating, not framing. The map surface extends behind
    the status bar and behind the bottom drawer. The stamp-count header becomes
    a floating pill over the map. The current-location control is circular and
    uses `.ultraThinMaterial`. The `Apple Maps / Legal` attribution sits over
    the map, not in an opaque band.
  - **A3.** Unselected markers are lightweight: a small filled dot carrying
    category color only — no `.regularMaterial`, no tint fill, no stroke, no
    shadow. Selected/focused markers expand to the current full marker treatment.
    Touch target stays >= 44pt (already correct in `DefaultPOIMarker`; must not
    regress).
  - **A4.** Brand identity survives. SAV-E must still not look like stock Apple
    Maps. Identity comes from marker color, chrome shape, and typography — not
    from desaturating the basemap. If the founder judges `.automatic` too loud
    against forest/honey, at most ONE tint layer may be reintroduced, recorded
    with a reason in code.

- Failure fixture: Any of the following fails the task —
  - reintroducing a second basemap-greying layer without a recorded reason
  - marker touch target below 44pt
  - unselected and selected markers rendered identically
  - chrome that leaves an opaque band on any edge of the map
  - claiming visual improvement from a build-only result with no rendered
    screenshot evidence
  - changing map behavior (POI selection, `mapFeatureSelectionDisabled`,
    clustering, region logic) while claiming a visual-only change

- Classification: Visual adjustment to an existing approved direction, not a new
  design system. Surface = `product-ui`. Mode = `adjustment`. No new paid
  capability, no product-flow change, no new data.

- Demand proof / pricing hypothesis / first distribution: Founder-observed
  defect against a direct Apple Maps side-by-side; no paywall claim and no
  monetization hypothesis attached. This is retention//legibility maintenance on
  the core surface. First distribution is `N/A` — no public proof artifact until
  it ships in a build the founder has seen rendered.

- Files and systems in scope:
  - `SAV-E/Views/Map/MapView.swift` — `.mapStyle` block, `DefaultPOIMarker`,
    `MapMarkerState`, `CurrentLocationButton`, context badge overlay
  - map chrome owners in `SAV-E/App/ContentView.swift` (`SaveMapRootView`
    invocation, `AtlasTabBar` placement) and `SAV-E/Views/Home/SaveRootViews.swift`
  - Out of scope: backend, parsing, Review pipeline, auth, payment, Trips,
    tab structure, any Feeds/tasks/3D work discussed separately.

- Verification:
  - Build-only tier for each slice:
    `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E
    -configuration Debug -destination 'generic/platform=iOS Simulator'
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/SAV-E-agent
    CODE_SIGNING_ALLOWED=NO build` must exit 0.
  - **UI tier is mandatory before this spec can be marked done.** A visual
    acceptance criterion cannot be proved by compilation. Boot exactly one
    headless simulator, capture the map screen before/after, verify shutdown.
  - Screenshot evidence must show the same region and zoom for before/after.
  - `git diff --check` clean.

- Security and privacy: No secrets, no production accounts, no real user places
  in screenshots — use the reviewer-demo fixture data. Map attribution must
  remain visible per Apple's MapKit terms; moving it over the map is allowed,
  hiding or obscuring it is not.

- Human approval still required: founder selection on A4 (how loud the basemap
  is allowed to be) after seeing rendered before/after, plus PR merge.

## Implementation order

Each slice is independently revertable. Do not batch.

1. **De-greying (landed, unverified visually).** Removed three of four greying
   layers; kept `emphasis: .automatic`. Code comment records why, so a future
   agent does not re-stack them. Build exits 0. **Rendered evidence not yet
   captured — A1 is not accepted until it is.**
2. **Chrome unframing.** Header pill floats; drawer/tab bar let the map through;
   location button circular + material; attribution over map. Highest visual
   payoff per line changed, and pure layout — no behavior touched.
3. **Marker weight.** Add an unselected/selected split to `DefaultPOIMarker`.
   Requires threading selection state, so it is the only slice with real
   regression surface. Keep the 44pt `contentShape`.

## Known open defect (investigate, do not fix blind)

The founder screenshot shows 73 Map Stamps but only 2 visible markers, one of
which renders as a plain dark-green circle with no glyph. That is either a
clustering/region bug or a missing-category fallback. It is **not** a styling
problem and must not be papered over by slice 3. File separately once
reproduced.

## Baseline gap (honest)

No before-screenshot was captured prior to slice 1 landing. The available
baseline is the founder's own screenshot of the shipped build, which is
sufficient for comparison but was not taken under controlled region/zoom. The
UI-tier verification must capture a controlled pair going forward.
