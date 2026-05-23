# Source Search Worker

## Summary
Execute source-only search recovery queries on the backend and write search-derived candidates back into Review.

## Problem
SAV-E can now produce search queries for URL-only social links, but those queries are inert unless a trusted backend worker executes them and records the results.

## Scope
- Add a backend public-search worker for source-only captures.
- Add `POST /memory/captures/:id/search-recovery`.
- Fetch public source URL metadata and use OpenGraph title/description as evidence before search fallback.
- Parse public search result titles/snippets into review-only place candidates.
- Reject generic platform, maps, search/list, and venue-directory results before creating candidates.
- Keep created candidates without coordinates and with verification missing info.
- Trigger recovery from native iOS when a source-only candidate is persisted.

## Non-goals
- No logged-in Instagram scraping.
- No paid search API or credential changes.
- No direct save to places.
- No automatic video download or frame OCR.

## Acceptance Criteria
- Source-only URL imports can trigger backend search recovery.
- Public source metadata with explicit place + address can create a review-only candidate before search results are considered.
- Search-derived results are inserted as `place_candidates` with `status = review`.
- Candidates include evidence pointing to query/result title/snippet/source URL.
- Generic results such as Instagram landing pages, Google Maps home/directions pages, Yelp search/list pages, Tagvenue/Eventective lists, and generic venue directories remain diagnostic-only and create no candidates.
- A search result can become a candidate only when it has explicit venue evidence: extracted address or an official venue signal from a non-blocked host.
- Existing candidate duplicates for the same capture are not reinserted.
- Backend tests, TypeScript build, iOS tests, and iOS generic build pass.
