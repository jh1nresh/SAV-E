# Design Directions

## Shared Product Truth

The direction is already locked as Illustrated Postcard Pocket. This pass does not reopen A/B/C; it refines the three inconsistent onboarding steps into that selected system.

## Experience Budget

- Context classification: first-run consumer travel-memory proof
- Workflow clarity: 55
- Reassurance and trust: 25
- Collectible delight: 20
- Character budget: one contextual Memo peek per screen; no repeated mascot decorations

## Selected — One Postcard, Three States

- Product metaphor: the user drops one messy source ticket into SAV-E's pocket; Memo finds a likely place; the user stamps it into private memory.
- Screen mapping: Clue = coral source ticket; Review = sky candidate ticket with the source receipt behind it; Stamp = mint lifted saved postcard.
- State language: `Source Clue` -> `Needs your review` -> `Confirmed by you`.
- Expressive mechanism: the same ticket silhouette and kraft envelope remain in the same stage position; color, seal, and visible metadata change.
- Strengths: direct production continuity, clear state semantics, low asset cost, distinctive SAV-E identity.
- Risks: the pocket could reduce editor space; long copy and keyboard avoidance need runtime verification.
- Implementation cost: medium, mostly component extraction and layout replacement in `OnboardingView.swift`.
- Production restraint: one Memo, one main ticket, one source receipt, one CTA; no decorative source-chip row or large fake map.

## Rejected Alternatives

- Form-first cleanup: clearer editor but remains visually separate from SAV-E.
- Atlas-first tutorial: visually rich but wrongly suggests map/navigation is the main product.

## Recommendation

- Selected by maker: One Postcard, Three States.
- Evidence: it is the only option that directly reuses the locked Saves and Lifted Postcard grammar.
- Founder selection: inherited from the locked Postcard Pocket direction and the explicit request to match the current app.
