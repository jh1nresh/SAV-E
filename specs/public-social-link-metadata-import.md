# Public Social Link Metadata Import

> Last updated: 2026-05-22

> Superseded boundary: social links now follow
> `specs/share-extension-social-review-only.md`. Public metadata may create
> review candidates, but the Share Extension should not geocode social metadata
> directly into a Map Stamp.

## Goal

Let SAV-E import public Instagram/TikTok/Xiaohongshu-style social links when the public HTML metadata exposes enough place evidence, without pretending the app analyzed private content or video frames.

## Product Contract

- Public social links may be fetched with ordinary unauthenticated HTTP.
- The app can use OpenGraph/Twitter/canonical metadata and caption preview text.
- The app must not claim to watch videos, read comments, bypass login, or scrape private account content.
- A saved place requires an explicit place/address signal plus reliable coordinates.
- If the metadata is too weak, the import should fail into review/refinement instead of saving a guessed pin.

## Native iOS Share Extension

1. User shares an Instagram/TikTok/Xiaohongshu link to SAV-E.
2. SAV-E fetches public page metadata and optional thumbnail OCR.
3. SAV-E runs evidence through the shared social parser.
4. If evidence is strong enough, SAV-E saves pending review candidates.
5. If evidence is weak, SAV-E preserves source-only memory and asks for a map link, screenshot, or visible place details.
6. The main app Review flow handles confirmation/refinement before any saved place is created.

## Acceptance Criteria

- The Instagram Reel public metadata example for Chafinity in Costa Mesa can produce a review candidate.
- Social links without an explicit place/address do not save fake pins.
- AI fallback is allowed for non-social links only in the Share Extension direct-save flow.
- The extension does not default uncertain social imports to San Francisco or `(0, 0)`.
