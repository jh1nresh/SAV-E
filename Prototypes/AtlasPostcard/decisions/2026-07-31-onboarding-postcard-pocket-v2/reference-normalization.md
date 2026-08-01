# Reference Normalization

- Status: required — current production onboarding and the locked Atlas Postcard direction are supplied references
- Source: final first-run CI screenshots and `Prototypes/AtlasPostcard/design.md`
- Intended use: adapt the existing onboarding behavior into the selected Postcard Pocket construction

## Reusable Rules

- Keep the fixed header, 4-step postal progress rail, one dominant coral action, and one-screen-per-step flow.
- Teach the real state transition: Source Clue -> Review Candidate -> confirmed Map Stamp.
- Show the same physical object changing state instead of introducing a different layout on every step.
- Preserve source evidence and require the user to confirm before a Map Stamp exists.

## Product-Specific Values

- SAV-E lockup, Memo artwork, atlas typography, cream paper, kraft envelope, scalloped tickets, and semantic sky/coral/mint colors.
- Existing copy, accessibility identifiers, clue capture, completion callback, and 402 x 874 pt review viewport.

## Risky Assumptions

- Rights and ownership: use only existing SAV-E-owned assets; generated mockup imagery is directional and cannot become production art.
- Trade-dress risk: no external product layout or character is copied.
- Repo or stack mismatch: production remains native SwiftUI.
- Performance and mobile cost: no new full-screen raster or animation dependency.
- Accessibility, reduced motion, and fallback: state meaning must survive without motion; text remains live.
- Invented product behavior or claims: no auto-confirmation, public review publishing, or network result is implied.

## Missing Requirements

- Long localized copy and compact-height behavior must be verified during implementation.
- Exact motion timing is deferred to the production spec.

## Adoption Decision

| Input rule or value | Adopt / adapt / reject | Product-specific replacement | Reason |
|---|---|---|---|
| Large freeform clue editor | Adapt | A coral source-clue ticket with an editable lined body | Preserve input while matching the pocket metaphor |
| Evidence checklist card | Reject | Postal evidence marks on one sky review ticket | Checklist reads like a dashboard |
| Generic mini-map confirmation card | Reject | Lifted mint saved postcard with a small atlas crop | Production Map Stamp detail already uses this construction |
| One Memo moment per screen | Adopt | Memo peeks from the shared envelope | Character explains the state without competing with content |
