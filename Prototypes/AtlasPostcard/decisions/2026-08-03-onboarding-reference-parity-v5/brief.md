# Onboarding reference-parity v5 brief

## Contract

- **Paid user job / observed failure:** a new traveler must understand that a
  messy social clue remains attached to the place they explicitly confirm. The
  current proof stage can read as separate decorative cards because the rear
  envelope liner is occluded between the letter and the front pocket.
- **Classification:** narrow first-run visual parity maintenance; no product
  behavior, persistence, parser, map, payment, or release change.
- **Reference authority:**
  `/var/folders/s1/wcqn2x2n337bqb330k56n7y00000gn/T/codex-clipboard-419d5483-b730-4610-ac35-0babbbcb1420.png`.
- **Scope:** `OnboardingView.swift`, its existing owned envelope assets, and
  this decision record. Do not touch the onboarding flow, copy, identifiers,
  backend, or unrelated Atlas screens.
- **Done when:** at 402 x 874 pt, Clue, Review, and Map Stamp all show one
  continuous open envelope: two airmail side rails, a connected kraft rear
  liner visibly bridging behind the lower ticket edge, and one front pocket
  that overlaps the ticket without a transparent hole, detached triangle, or
  second envelope body. The retained coral/sky/mint cards and their Memo poses
  remain distinct and have no new generic card treatment.
- **Verification:** source parse, generic iOS build when local storage permits,
  focused `SAVEOnboardingCarouselTests`, and the CI `SAVE-First-Run` full-screen
  Clue / Review / Map Stamp screenshots. Visual parity is judged from the
  envelope foreground crop, not full-screen pixel similarity.
- **Risk / security:** UI-only local assets and layout. Security/privacy scan is
  N/A: no external data, permissions, credentials, network, or persistence path
  changes.
- **Demand / pricing / distribution:** reduce first-run trust ambiguity before
  public TestFlight demos; no pricing or paywall claim changes. The first
  distribution format is a validated onboarding demo screenshot, not a release.
- **Human boundary:** branch, commit, and pull request are allowed after
  verification. Merge, TestFlight, and deployment remain founder-approved,
  separate actions.

## Design brief

- **Direction:** illustrated postal proof object — playful, tactile, and
  deliberately constructed rather than a stack of generic cards.
- **Density:** comfortable; one central object, with the heading and CTA kept
  legible around it.
- **Surface:** owned paper, airmail, kraft, and postage textures with real
  occlusion; no decorative glass or free-floating panels.
- **Type mood:** warm, condensed, editorial.
- **Motion:** one short ticket-settle transition; reduced motion renders the
  final composition directly.
- **Do:** preserve one shared coordinate system; expose a restrained kraft rear
  mouth lip; terminate rails behind the front pocket; keep state colors semantic;
  validate each screen with the same viewport crop.
- **Don't:** add a second pocket/flap, place a separate decorative triangle on
  top, let cards fully occlude the liner, or use a whole-screen generated image
  as UI.

## Topology contract

```text
rear airmail liner
  -> state ticket / source crown
  -> visible kraft rear-mouth lip
  -> front kraft pocket
  -> Memo peek
```

The rear-mouth lip is a shared part of the same envelope, not a third card or
independent sticker. It must be visible only where the ticket enters the front
pocket, with both ends tucked behind the front-pocket shoulders.
