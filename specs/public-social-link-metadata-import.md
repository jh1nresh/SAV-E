# Public Social Link Metadata Import

> Last updated: 2026-05-13

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
2. SAV-E fetches public page metadata.
3. If metadata includes an explicit address, SAV-E extracts:
   - place name
   - address
   - category
   - source URL
4. SAV-E geocodes the explicit address to coordinates.
5. If geocoding succeeds, SAV-E saves the pending place to shared app storage.
6. If metadata or geocoding is not reliable, SAV-E shows a no-guessing error and asks for a map link or visible place details.

## Acceptance Criteria

- The Instagram Reel public metadata example for Chafinity in Costa Mesa can produce a saveable pending place.
- Social links without an explicit place/address do not save fake pins.
- AI fallback is allowed only after meaningful metadata is present and must still pass coordinate/city validation.
- The extension does not default uncertain social imports to San Francisco or `(0, 0)`.
