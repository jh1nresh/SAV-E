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
- The existing SAV-E logo, Memo, owned envelope, atlas, paper, and native shape
  assets are reused. The new owned `OnboardingNightCafe` fixture records its
  built-in generation prompt and deterministic 1x/2x/3x outputs.
- The fixed viewport has no `ScrollView`; primary and skip actions remain
  visible at 402 x 874 pt.
- Reduced Motion renders the final proof composition immediately.

## Intentional Deviations

- The generated concept's decorative map is replaced by the owned
  `MapAtlasScene` fixture. The cafe slot uses the separately generated,
  provenance-recorded `OnboardingNightCafe` asset rather than a crop of the
  whole design board.
- Review uses a compact retained coral receipt behind the sky candidate ticket
  instead of the generated full-size source card, preserving provenance and
  the fixed subtitle at the approved viewport.

## Founder Fidelity Correction — 2026-08-01

The earlier rail-only correction removed the unintended full cream backing
body but also removed the rear envelope shoulder/top edge. It left detached
coral/sky tabs and retained three oversized white cards. That ruling was too
narrow and is superseded.

The corrected implementation:

- replaces the Canvas approximation with one owned section-level
  `OnboardingAirmailEnvelopeBack` vector asset containing the connected striped
  border, cream shoulder, top flap, and fold lines;
- keeps the lower shell behind the owned kraft pocket, so it cannot read as a
  third full backing card;
- narrows and state-tints the Clue, Review, and Map Stamp cards;
- restores the Review source receipt and the approved Map Stamp information
  order; and
- moves Memo from the printed seal center to a peek over the pocket mouth.

The final fidelity pass also removes the extra Clue privacy label, restores the
approved airplane sample action and exact Review subtitle, uses one owned moon
mug illustration instead of a generic SF Symbol, repeats the approved source
proof caption on all three pockets, and places the Map Stamp paperclip and
postal cancellation over the photo area.

## Visible Rear-Envelope Correction — 2026-08-01

The previous regular-height geometry placed the rear airmail envelope 70 pt
above the stage bottom. The state cards extended above that asset, so the
connected shoulder and top flap were fully occluded and the remaining sides
read as two unrelated color rails. The shared rear-envelope layer now sits
112 pt above the stage bottom (68 pt in compact height), exposing its connected
top edge on Clue, Review, and Map Stamp while its lower edge remains behind the
kraft front pocket.

The narrow 1491 x 234 comparison crop is rejected as visual evidence because
it removes the kraft pocket, Memo, postal seal, and fixed actions. The ship gate
remains the three full 402 x 874 pt same-commit screenshots.

The previous fidelity pass completed its generic iOS Simulator build with
`BUILD_EXIT=0`. This visible-envelope correction remains gated by a fresh build
and full same-commit Clue, Review, and Map Stamp runtime screenshots.

## Open-Envelope Continuity Correction — 2026-08-01

The 112 pt reveal exposed the complete artwork for a *closed* rear envelope,
then placed the kraft pocket in front of it. Although no asset was missing, the
result read as two envelopes cut apart and stacked. That geometry ruling is
superseded.

The rear artwork is now an open liner: one striped shoulder, continuous side
rails, and a subtle curved inner-mouth seam. Its regular-height offset is 92 pt
(58 pt compact), and its 342 pt width matches the rendered kraft pocket. The
state ticket is the only object emerging from the shared mouth; there is no
second flap or separate cream envelope body.

## Envelope Topology and Card-Proportion Correction — 2026-08-01

The open-liner correction above still encoded the rear layer as a complete
striped rectangle with a cream inset. In runtime that exposed a horizontal
airmail bar above every ticket and made the old kraft pocket read as a second,
detached rectangle. Matching colors and z-order was not enough; the reference
requires a different physical topology.

This pass replaces the rear rectangle with one V-folded open-envelope back:

- the outer airmail material is visible only as narrow side rails;
- diagonal kraft shoulders sit between those rails and the ticket;
- both folds meet at a central tip beneath the letter;
- the front `SavesEnvelope` mouth overlaps that tip and the lower ticket edge;
- the Clue, Review, and Map Stamp cards regain the taller proportions and
  evidence order visible in the approved direction; and
- the Review backing card becomes a deliberate coral source crown rather than
  an almost-empty generic receipt.

The Clue receipt date is rendered once. The Map Stamp uses a larger clipped
photo, postal cancellation, source receipt, and atlas strip before entering the
same pocket.

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
