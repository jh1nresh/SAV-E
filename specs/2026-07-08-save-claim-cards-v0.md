# SAV-E Claim Cards v0 — Private Memory First

> Created: 2026-07-08
> Brain source: `/Users/jhinresh/brain/raw/inbox/2026-07-08-save-claim-cards-v0.md`
> Related: `specs/2026-06-03-verified-place-claims-api.md`, `specs/save-search-reviews-receipts-v0.md`, `specs/save-memory-layer.md`

## Decision

Build SAV-E's “optimized review system” as **private-first Claim Cards**, not as a public review wall.

```text
messy place signal
→ Review Candidate with evidence
→ user confirms / edits / rejects
→ structured claims with proof level
→ Ask SAV-E / search / recommendation uses trusted claims
→ public/link-shared cards later only after proof exists
```

Do **not** position this as “a better Yelp / Google Maps reviews app.” The wedge is personal place memory and trusted, contextual, agent-usable claims.

## Why this is the right slice

- Public reviews are cold-start heavy and moderation-heavy.
- Natural-language reviews are too vague for agents.
- The immediate user value is: “My SAV-E remembers places I saved, tried, rejected, and trusted.”
- Each confirm/edit/reject creates Task-Economy-grade data: source evidence, candidate, user verdict, correction, claim context, proof level.
- This strengthens the existing Verified Place Claims thesis without adding public feeds, payments, booking, or broad agent marketplace scope.

## Product object

A Claim Card is a human-readable card backed by structured claims.

Minimum fields:

```ts
type SaveClaimCard = {
  cardId: string
  placeId: string
  title: string
  status: 'review_candidate' | 'confirmed_place' | 'tried' | 'rejected'
  sourceRefs: string[]
  evidenceSummary: string[]
  strongestProofLevel:
    | 'source_backed'
    | 'user_confirmed_place'
    | 'visited_self_reported'
    | 'friend_verified'
    | 'receipt_backed'
  claims: SavePlaceClaim[]
  missingInfo: string[]
  visibility: 'private' | 'link_shared'
  updatedAt: string
}

type SavePlaceClaim = {
  claimId: string
  claimType:
    | 'want_to_go'
    | 'went_before'
    | 'good_for_date'
    | 'good_for_group'
    | 'good_for_work'
    | 'long_wait'
    | 'order_this'
    | 'avoid_this'
    | 'too_expensive'
    | 'friend_verified'
  value: boolean | string | number
  agentUsableSummary: string
  proofLevel: SaveClaimCard['strongestProofLevel']
  confidence: number
  observedAt?: string
  expiresOrStaleAfter?: string
}
```

## UX contract

Never start from a blank “write a review” form.

Start from what SAV-E already knows:

```text
SAV-E found:
- likely place
- source/evidence
- suggested claims
- missing info

User actions:
[去過] [想去] [不是這家] [朋友推薦] [不適合我] [下次點這個]
```

Claim data should grow from capture + one-tap correction.

## First engineering slice

### Backend / data

- Add owner-scoped `place_claims` or equivalent local/backend claim storage.
- Attach claims to existing places and/or review candidates.
- Preserve evidence refs and proof levels.
- Keep private by default.
- Expose only owner-scoped claim read/write paths through `save-api`.

Suggested minimal routes, if consistent with current API style:

```http
GET  /v0/places/:placeId/claim-cards
POST /v0/places/:placeId/claim-cards
PATCH /v0/claim-cards/:cardId
GET  /v0/places/:placeId/trust-summary
```

If route nesting conflicts with current `save-api` routing, Codex should pick the smallest compatible shape and document it in the PR.

### UI

Add one private Claim Card surface, not a public review page:

- shows evidence summary;
- shows suggested claims as chips;
- lets user confirm/edit/reject;
- clearly separates `Review Candidate` from confirmed saved place;
- exposes proof level labels in plain language.

### Ask/search integration

If already cheap in this slice, saved-place search / Ask SAV-E can cite claim summaries. If not, leave a typed TODO and test the data contract first.

## Out of scope

- Public review feed.
- Likes/comments/follows.
- Public collections.
- Paid/API access.
- Booking/order/payment/message automation.
- Publishing raw private sources.
- Friend graph import.
- On-chain receipts.
- Broad AgentShack listing.

## Security / privacy gates

This touches private evidence and owner-scoped place memory, so Engineering must include a security receipt:

- Verify every route filters by verified Privy subject / `user_id`.
- Service-role backend must not expose another user's claims or raw evidence.
- Public/link-shared support is out of scope unless explicit publish controls exist.
- No raw friend messages, receipts, payment details, screenshots, or source payloads in public projections.
- No external side effects.

## Customer-value eval

Use this failure taxonomy before calling the slice good:

```text
F1 place identity wrong
F2 weak source became confirmed place
F3 evidence/proof missing or misleading
F4 user cannot quickly correct claim
F5 claim is too vague for Ask SAV-E to use
F6 private source leaks into public/shared output
F7 search/recommendation ignores the claim
```

Seed examples:

1. Instagram/TikTok/social post with one venue and weak evidence.
2. Google Maps link to a known place.
3. User says “went before, not good for work, good for date.”
4. User rejects a wrong candidate.
5. User later asks: “找一個適合 casual date、不想排隊太久的地方.”

Pass condition:

- Claim Card keeps uncertain places in review.
- User can confirm/edit/reject in one short interaction.
- Trust summary / search can cite claim evidence without exposing private raw source.

## Demand / distribution check

Demand proof to validate before building public layers:

- 10 real captured places from founder/friends.
- At least 6 produce useful Claim Cards.
- At least 3 later searches/asks use a saved claim in the answer.
- User says the claim memory changed a choice or prevented re-checking old links.

First distribution artifact after implementation:

```text
messy social place post
→ SAV-E Review Candidate
→ one-tap Claim Card
→ Ask SAV-E recommends using proof labels
```

This should become an App Store / public proof video, not a social-feed launch.

## Verification

Suggested commands / checks:

- Inspect `supabase/schema.sql` and `supabase/functions/save-api/index.ts` before editing.
- Add migration/schema coverage for claims.
- Add route-level owner-scope tests or a small scripted smoke test if the repo has no test harness.
- Run the smallest available backend TypeScript/Deno check.
- If UI is touched, run the smallest available app build/smoke path and include skipped-check reasons if unavailable.
