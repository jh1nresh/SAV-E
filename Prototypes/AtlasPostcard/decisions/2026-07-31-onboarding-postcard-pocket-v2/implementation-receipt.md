# Implementation Receipt

## Implemented Direction

One Postcard, Three States: the first-run Clue, Review Candidate, and Map Stamp
screens now share one Postcard Pocket construction and the existing SAV-E
Atlas shell.

## Files Changed

- `SAV-E/Views/Onboarding/OnboardingView.swift`
- `Tests/SAVEUITests/SAVEOnboardingCarouselTests.swift`
- This selected design-decision package and runtime evidence.

## Rules Preserved

- `Language -> Clue -> Review Candidate -> Map Stamp` remains the product flow.
- Coral, sky, and mint retain their Source Clue, Review Candidate, and confirmed
  Map Stamp meanings.
- User confirmation remains mandatory before the proof becomes a Map Stamp.
- Source retention stays visible through ticket copy and the pocket caption.
- The existing SAV-E logo, Memo, owned envelope, thumbnail, atlas, paper, and
  native shape assets are reused; no external or generated production asset was
  added.
- The fixed viewport has no `ScrollView`; primary and skip actions remain
  visible at 402 x 874 pt.
- Reduced Motion renders the final proof composition immediately.

## Intentional Deviations

- The generated concept's cafe illustration and decorative map are replaced by
  owned `KoffeeMameyaThumbnail` and `MapAtlasScene` fixtures.
- Review uses a compact retained coral receipt behind the sky candidate ticket
  instead of the generated full-size source card, preserving provenance and
  the fixed subtitle at the approved viewport.

## Founder Fidelity Correction — 2026-08-01

The earlier rail-only correction removed the unintended full cream backing
body but also removed the rear envelope shoulder/top edge. It left detached
coral/sky tabs and retained three oversized white cards. That ruling was too
narrow and is superseded.

The corrected implementation:

- restores one partial cream shoulder/top edge connected to the side rails;
- keeps the lower shell behind the owned kraft pocket, so it cannot read as a
  third full backing card;
- narrows and state-tints the Clue, Review, and Map Stamp cards;
- restores the Review source receipt and the approved Map Stamp information
  order; and
- moves Memo from the printed seal center to a peek over the pocket mouth.

Generic iOS Simulator build passed with `BUILD_EXIT=0`. Fresh same-commit Clue,
Review, and Map Stamp runtime screenshots remain the ship gate for this
correction.

## Build and Test Result

- `swiftc -frontend -parse`: passed.
- Generic iOS Simulator build: `BUILD SUCCEEDED`.
- Focused UI test:
  `SAVEOnboardingCarouselTests.testProofFirstFlowReachesOpenAppCTA` passed with
  1 test and 0 failures.
- Storage lifecycle receipts: build and runtime both `PASS`; runtime finished
  with 0 lifecycle violations.

## Actual UI Screenshots

- `evidence/clue.png`
- `evidence/review.png`
- `evidence/map-stamp.png`

Each image is 1206 x 2622 px, corresponding to the approved 402 x 874 pt
iPhone viewport at 3x.

## Accessibility and Reduced Motion

- Existing onboarding control identifiers are preserved.
- Review and Map Stamp expose one combined proof-stage description plus a
  deterministic `preparing` / `ready` value; the UI test waits for `ready`
  before capture.
- Decorative evidence marks remain inside the combined proof description.
- Reduced Motion behavior remains implemented; a separate VoiceOver/manual
  audit was not run in this slice.

## Remaining Gaps

- Long Traditional Chinese copy and keyboard-open composition were not captured
  in this English proof fixture.
- App Store/TestFlight deployment is outside this PR and still requires explicit
  human approval.
