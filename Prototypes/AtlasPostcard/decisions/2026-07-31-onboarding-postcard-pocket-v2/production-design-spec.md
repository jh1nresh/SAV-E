# Production Design Spec

SAV-E Onboarding Postcard Pocket v2

## Design Thesis

First run demonstrates one physical SAV-E object changing state. A messy
Source Clue enters the kraft pocket, returns as a Review Candidate, and lifts
out as a private Map Stamp only after the user confirms it. Onboarding must
look like the production Saves system, not a feature carousel or form demo.

Approved direction mockup:
`approved-direction.png`.
The generated pixels are directional fixtures and are not production assets.

## Experience Budget

- Workflow clarity: 55%
- Reassurance and trust: 25%
- Collectible delight: 20%
- Character budget: one contextual Memo peek per screen

## Tokens

Use the existing `SaveAtlasPalette` and `SaveAtlasType` without a second token
set. Coral is the only primary action; coral/sky/mint describe Clue, Review,
and confirmed states respectively.

## Navigation and Viewport

- Preserve the current fixed back button, Memo + SAV-E lockup, step seal,
  Language / Clue / Review / Stamp rail, bottom primary action, and skip action.
- No root tabs and no `ScrollView`.
- Review viewport: 402 x 874 pt; compact layout remains supported below 760 pt.
- The pocket stage occupies one stable central region across all three pages.

## Component Inventory

- `OnboardingTopBar`: unchanged behavior and identifiers.
- `OnboardingStepTitle`: compact title above the pocket stage.
- `OnboardingPocketStage`: shared owned kraft envelope, contextual Memo, and
  retained-source presentation.
- `OnboardingAirmailEnvelopeBack`: owned open-liner illustration with broad
  kraft side wings and narrow striped outer rails. Its centre stays transparent
  above the pocket so the state ticket is the only visible central sheet.
  A closed-envelope flap, a second backing card, or disconnected stripes fail
  the open-envelope silhouette.
- `OnboardingSourceTicket`: coral scalloped editable lined ticket and sample
  postage action.
- `OnboardingReviewTicket`: sky scalloped ticket, candidate name, owned
  `OnboardingMoonMug`, three postal evidence marks, retained coral source
  receipt.
- `OnboardingSavedPostcard`: mint scalloped lifted header, photo, confirmation
  seal, source receipt, cancellation lines, and small decorative atlas fragment.
- Existing `SavePostcardScallopedRectangle`, `SavePostcardSealShape`,
  `SavePostcardPostmark`, `MemoMascotMark`, and owned image assets.

## State Matrix

| State | Surface | Required truth | Main action |
|---|---|---|---|
| Source Clue | coral ticket | messy text, source retained, not a place | Find this place |
| Review Candidate | sky ticket | likely place, source retained, exact pin still uncertain | Confirm this place |
| Map Stamp | mint saved postcard | confirmed by user, private, source retained | Open SAV-E |

## Expressive Mechanisms

- The envelope remains spatially stable while the ticket advances forward.
- The airmail liner and front kraft pocket read as one open envelope around the
  state ticket. The ticket is narrower than the pocket, and the shared pocket
  mouth covers its lower edge without creating a second horizontal seam.
- The rear liner stays visible only as the two diagonal shoulders beside each
  state card at the 402 x 874 reference viewport. The front pocket owns the
  shallow centre point and mouth seam; no second central flap is rendered.
- Memo appears once at the envelope edge to explain the current state.
- Review keeps the coral source receipt visible behind the sky ticket.
- Map Stamp reuses the saved-postcard structure, not a large fake map.

## Motion and Reduced Motion

- Standard mode: a short spring settles the ticket into, forward from, or up
  from the pocket; evidence marks may arrive with short staggered fades.
- Reduced Motion: render the final composition immediately; never hide evidence
  or remove progress meaning.
- No continuous breathing, parallax, or cycling animation.

## Assets and Ownership

- Allowed: `OnboardingAirmailEnvelopeBack`, `OnboardingEnvelopeFront`,
  `OnboardingMemoClue`, `OnboardingMemoReview`, `OnboardingMemoStamp`,
  `SavesMemoSorting`, `MemoMascot`, `OnboardingNightCafe`, `PaperTexture`, and
  code-native Atlas shapes.
- Generated concept-fixture crops are rejected as production assets. The three
  separately generated Memo poses and blank onboarding pocket are allowed only
  with their prompt, identity reference, ownership route, alpha conversion,
  and 1x/2x/3x outputs recorded in the asset manifest.
- No new dependency or external image URL.

## Exact Copy and Typography

- Clue: `Drop one messy clue`; `A link, caption, or note is enough.`;
  `Source Clue`; `Try sample`; `Find this place`.
- Review: `Memo found a likely place`; `It stays in review until you confirm.`;
  `Review Candidate`; `Hidden Moon Cafe?`; `Name found`; `Source kept`;
  `Exact pin missing`; `Confirm this place`.
- Map Stamp: `You confirmed it. Stamped.`; `Only places you confirm become
  private Map Stamps.`; `Confirmed by you`; `Hidden Moon Cafe`;
  `Source retained · Private`; `Open SAV-E`.
- Traditional Chinese uses the existing `AppLanguage.localized` route.
- Avenir Next Condensed via `SaveAtlasType`; no SF Rounded substitute.

## Accessibility

- Preserve `onboarding.clueEditor`, `onboarding.sampleClue`,
  `onboarding.primary`, `onboarding.skip`, and top-bar identifiers.
- Keep the proof stage as one combined accessibility description per state.
- Primary and sample actions retain 44 pt minimum hit targets.
- Semantic meaning may not depend on color or motion alone.
- Text scales and uses line limits/minimum scale only where the approved fixed
  composition requires it.

## Real Data Replacements

- `clueText` remains real local user input.
- Candidate/place names are clearly labeled local proof fixtures; no network
  lookup is implied.
- The final place image uses the owned `OnboardingNightCafe` fixture only as a
  visual example; it is not persisted as user data.
- The Review mug is an owned local vector illustration and is decorative only.

## Implementation Order

1. Replace floating Clue chips and blank editor card with the shared pocket
   stage and editable coral source ticket.
2. Replace `ProofDemoCanvas` Review checklist with the retained source receipt
   and sky review ticket.
3. Replace `OnboardingMiniMap` with the mint lifted saved postcard.
4. Preserve tests/identifiers, then run build-only and focused UI gates.

## Visual Verification

- Export Clue, Review, and Map Stamp from `SAVEOnboardingCarouselTests`.
- Compare against this spec at 402 x 874 pt, checking shared anchors rather
  than pixel-matching generated imagery.
- Required: same pocket silhouette and stage anchor, source continuity, state
  color semantics, one Memo moment, one coral CTA, no clipping/scrolling.
- Card fidelity is structural: Clue is a narrow coral lined ticket; Review is
  a compact sky ticket over a visible coral source receipt; Map Stamp is a
  mint saved postcard with the photo at upper-right, source receipt above the
  atlas strip, and postal cancellation detail. A shared oversized white panel
  with state-colored borders does not pass.
- Memo must peek over the pocket mouth. Placing the mascot in the center of the
  printed wax seal does not pass.

## Residual Risks

- Keyboard presentation and long Traditional Chinese copy need runtime proof.
- The approved 402 x 874 pt English fixture is verified; long Traditional
  Chinese copy and keyboard presentation remain follow-up runtime checks.

## Implementation Gate

- Target repo: `/Users/jhinresh/projects/wanderly-current`
- Approved direction: One Postcard, Three States
- Screens and states in scope: Clue, Review Candidate, Map Stamp onboarding
- Existing components to preserve: flow state, top bar, bottom actions,
  localization, accessibility identifiers, callbacks
- Generated fixtures to replace: generated photo/map/Memo with owned assets and
  native shapes
- Implementation skill route: Swift/Xcode workflow + SwiftUI UI patterns
- Build or preview command: canonical generic build in the implementation brief
- Visual verification viewports: 402 x 874 pt; compact-height sanity check
