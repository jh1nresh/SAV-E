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

`--destination` runs the prototype XCTest `testCaptureFourLockedScreens`
and compares only Home, Saves, Plan, and Map. That prototype shell has
no Friends tab, so a local four-screen pass is not Friends evidence.
CI result-bundle mode gates live `five-tab-friends` at 0.90 against
`ProductionTargets/friends.png` (the DESIGN v2 `friends-light.png`
lock). Home deferral on #290 does not apply to Friends. Codex packet spec §7.4 remains the people-first layout reference. Live
`five-tab-friends` attachments still ship in the iOS First-Run
artifact. XCTest locks the application window to 402 × 874 points;
the Home/Saves/Plan/Map comparator accepts only exact, uniform Retina
pixel multiples of that viewport and rejects other dimensions.

Production parity uses `Reference/ProductionTargets`. The original
`Reference/Targets` remain the immutable inputs for deterministic illustration
extraction, so approving a UI refresh cannot silently alter generated assets.

The Home production target is DESIGN v2's exact 402×874
`home-light.png` from `design/doodle-targets-2026-10-20` at `eade369`.
`home-dark.png` sits next to it for DESIGN comparison.
`home-mask.png` is the ignore mask (white = ignore). Grade position,
size, color and font style. v1 is retired. Those rasters are rendered
at 1× 402×874, not a crop. `VisualParity.swift` still accepts only a
1× 402 × 874 target. Founder sign-off 2026-10-20:
「改成跟手繪稿比對，門檻維持 0.90」. Saves, Plan, and Map targets stay
on their current locks until those Doodle PRs. The `0.90` threshold
remains unchanged.

## Boundaries

- Seeded display data only.
- Existing `MemoMascot` artwork is copied unchanged from Savvy.
- No production source file is linked into this target.
- No shipping decision should be made from code alone; review all four
  screenshots against `design.md`.
