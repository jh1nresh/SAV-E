# SAV-E Search, Reviews, Receipts v0

## Scope

Implement the first local foundation for searchable SAV-E memory:

- Search saved places, pending review clues, source-only clues, and tried memories.
- Keep results split into `From your SAV-E` and `New recommendations`.
- Add a private-first review draft schema with receipt-ready proof references.
- Keep new recommendations as an unsaved shell only.

## Product Rules

- Weak social evidence stays review-scoped.
- Source URLs are evidence, not the primary title.
- New recommendations must not be mixed into saved memories.
- Private reviews are private by default.
- Receipt-backed reviews are schema-only in this cut; no wallet, chain write, payment call, or public posting.

## Out of Scope

- Push/local notification scheduling.
- Full review CRUD.
- Receipt ingestion.
- On-chain attestations or commitments.
- Backend recommendation sync.
- Logged-in social scraping, video OCR, or broad OSINT.

## Acceptance

- Search can return saved, pending, source-only, tried, and review-shaped objects.
- Visited places surface as tried memories.
- Source-only and pending items stay out of map-pin state.
- Recommendation intent creates only an unsaved recommendation shell.
- Tests cover local search sections, review-scoped records, tried memories, and private receipt-ready review schema.
