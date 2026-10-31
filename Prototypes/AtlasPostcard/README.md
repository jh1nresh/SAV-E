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

`--destination` runs the prototype XCTest `testCaptureFourLockedScreens` and compares only Home, Saves, Plan, and Map. That prototype shell has no Friends tab, so a local four-screen pass is not Friends evidence. Its legacy Home may fail the current native Home target; CI result-bundle mode remains the production evidence route. CI gates live `five-tab-friends` at 0.90 against `ProductionTargets/friends.png`, the founder-approved native raster; historical `friends-light.png` is archive only. Home deferral on #290 does not apply to Friends. Codex packet spec §7.4 remains the people-first layout reference. Live `five-tab-friends` attachments still ship in the iOS First-Run artifact. XCTest locks the application window to 402 × 874 points; the Home/Saves/Plan/Map comparator accepts only exact, uniform Retina pixel multiples of that viewport and rejects other dimensions.

Production parity uses `Reference/ProductionTargets`. The original
`Reference/Targets` remain the immutable inputs for deterministic illustration
extraction, so approving a UI refresh cannot silently alter generated assets.

The Home production target is the founder-approved native raster
`Reference/ProductionTargets/home.png`
(md5 `a4d08600dfba758e1ac714894ef02728`), approved on 2026-10-28 after
the existing-versus-current comparison. Historical DESIGN v2
`home-light.png` at `eade369` is archive only. Home grades unmasked
at 0.90 and must pass. Future raster changes still require the founder's
personal approval; do not add a Home mask or lower the threshold.
`home-dark.png` is DESIGN comparison only and
does not enter parity. `VisualParity.swift` still accepts only a
1× 402 × 874 target. Unmasked Home uses the legacy composite; the
optional `--mask` path reports position, size, color, and fontStyle
sub-scores but is not applied to Home. The Map production target is the
native Taipei CI raster personally approved on 2026-10-31 after the old/new
comparison: PR #330, run `41150737985`, head
`5dcf3a00a0298d201424a2a0ca4525ff52abdd1a`, artifact `13027256967`.
`map.png` retains the exact 3× 1206×2622 CI pixels (402pt viewport), SHA-256
`110d330a6aad69a7597f8396d1e66d5f34c342cf37cbe7dc4b114d477241bdf8`;
it is not cropped or resampled. The selected native Cafe marker matches its
card, with a stable bottom safe area for the overlaid search shelf. This
supersedes the #298 light Map target. Dark Map and all other reference
images remain unchanged; `map-mask.png` is not applied to the 0.90 score. Saves and
Plan stay on their current locks until those Doodle PRs. The `0.90`
threshold remains the CI gate for Home, Map, Saves, and Plan.

The same personal approval covers Friends, Capture, Paywall and Passport.
These five targets come from CI run `40654854143`, head
`b68f9824c7dd672f8bef92f463fbf8a6acbcd66b`, uniformly normalized from
1206×2622 to 402×874. Paywall is the CI offline unavailable-product / Retry
state; approving its raster does not change prices, products or purchasing.
No threshold, ignore region, mask or other reference image changed.

The Passport light production target is the native raster personally approved
on 2026-10-30 from PR #330 full CI run `40991924628`, head
`9e13338daafe4f52ae9cd83d5e3c9c483627ce7e`, normalized from 1206×2622 to
402×874 RGB with Lanczos resampling. Only `passport.png` was updated.
Historical `passport-light.png` from `design/doodle-targets-2026-10-20` at
`eade369` is archive only; `passport-dark.png` remains a DESIGN comparison.
These rasters use 1× 402×874, not a crop. The light face shows identity,
edit/settings actions above stickers and cities, with Passport selected
in the five-tab rail. The former sticker-only layout is superseded. `VisualParity.swift` still accepts only a 1× 402 × 874
target. The `0.90` threshold is a hard CI gate for Passport; there is
no passport ignore mask.


## Boundaries

- Seeded display data only.
- Existing `MemoMascot` artwork is copied unchanged from Savvy.
- No production source file is linked into this target.
- No shipping decision should be made from code alone; review all four
  screenshots against `design.md`.
