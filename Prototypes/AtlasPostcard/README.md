# Savvy Atlas + Postcard Prototype

This is an isolated, disposable iOS visual prototype. It does not import or
modify the production Savvy views, navigation, models, persistence, auth, or
networking.

The prototype exists to answer one question before production implementation:

> Does the approved Little Atlas + Postcard Pocket direction feel unmistakably
> like the reference when it is rendered as a real iOS interface?

## Build

```bash
cd Prototypes/AtlasPostcard
xcodegen generate
xcodebuild \
  -project AtlasPostcardPrototype.xcodeproj \
  -scheme AtlasPostcardPrototype \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-AtlasPrototype" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Regenerate approved section assets

```bash
cd Prototypes/AtlasPostcard
node Scripts/extract-reference-assets.mjs
```

The extractor is local and deterministic. It creates only section-level
illustrations and thumbnails listed in `Reference/asset-manifest.json`; it
does not create a whole-screen screenshot background. It requires Python 3
with Pillow and exits with an installation hint when Pillow is unavailable.

## Visual parity gate

Use one task-owned 402 × 874 iPhone Simulator:

```bash
Scripts/run-visual-parity.sh \
  --destination 'platform=iOS Simulator,id=<UDID>' \
  --artifacts /absolute/path/to/new-empty-artifact-directory
```

The runner captures Home, Saves, Plan, and Map, then writes matching
`reference/`, `output/`, `diff/`, and `results/` directories. All four pages
must score at least `0.90`. XCTest locks the application window to 402 × 874
points; the comparator accepts only exact, uniform Retina pixel multiples of
that viewport and rejects other dimensions.

Production parity uses `Reference/ProductionTargets`. The original
`Reference/Targets` remain the immutable inputs for deterministic illustration
extraction, so approving a UI refresh cannot silently alter generated assets.

The Home production TARGET is still the old
`Reference/ProductionTargets/home.png` baseline
(md5 `79ae24aaf02002cd10f429c2869dcfc0`), **not** DESIGN v2
`home-light.png` at `eade369`. That v2 raster is archive / DESIGN
comparison only until the founder personally approves a new Home
baseline. Home grades unmasked against the old target at 0.90; the
score is expected to FAIL on the current list-only Home and is not
evidence. Do not swap `home.png`, do not add a Home mask, and do not
lower the threshold. `home-dark.png` is DESIGN comparison only and
does not enter parity. `VisualParity.swift` still accepts only a
1× 402 × 874 target. Unmasked Home uses the legacy composite; the
optional `--mask` path reports position, size, color, and fontStyle
sub-scores but is not applied to Home. The Map production target is the
live Taipei Apple Maps CI capture (iPhone 16 Pro, 402pt, 3× 1206×2622)
from #298; `map-mask.png` is not applied to the 0.90 score. Saves and
Plan stay on their current locks until those Doodle PRs. The `0.90`
threshold remains the CI gate for Home, Map, Saves, and Plan.


## Boundaries

- Seeded display data only.
- Existing `MemoMascot` artwork is copied unchanged from Savvy.
- No production source file is linked into this target.
- No shipping decision should be made from code alone; review all four
  screenshots against `design.md`.
