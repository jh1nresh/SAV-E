# SAV-E Railway Backend

Railway-hosted API for SAV-E mobile persistence. It replaces the previous Supabase Edge Function while preserving the iOS API contract.

## Environment

```bash
DATABASE_URL=postgresql://...
PRIVY_APP_ID=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
PORT=3000
```

Railway provides `DATABASE_URL` and `PORT`. Set the Privy values on the backend service.

## Local

```bash
npm install
npm run build
npm run start
```

Apply schema:

```bash
psql "$DATABASE_URL" -f backend/sql/schema.sql
```

## Routes

Persistence routes accept either `Authorization: Bearer <Privy access token>` or `x-save-guest-id: guest_<uuid>`.

- `GET /places`
- `POST /places`
- `PATCH /places/:id`
- `DELETE /places/:id`
- `PATCH /places/:id/visibility` — opt a saved place into friends/public social signals; `private` disables all social signal flags.
- `POST /follows` — follow another profile by `following_id`, `handle`, or `referral_code`.
- `GET /social/signals?lens=forYou|friends|trending` — returns friend/trending social place rows from explicit follows and visibility opt-ins only.
- `GET /referrals/:code` or `GET /referrals?handle=:handle` — public referral profile preview with opted-in featured places.
- `GET /trips`
- `POST /trips`
- `PATCH /trips/:id`
- `DELETE /trips/:id`
- `GET /profile`
- `PATCH /profile`
- `POST /memory/captures/:id/search-recovery` — runs public search recovery for source-only captures and writes search-derived results back as review-only place candidates.
- `GET /v0/places/:id/verified-claims` — returns owner-scoped place claims; raw evidence refs are omitted unless `includePrivateEvidence=true`.
- `POST /v0/places/:id/verified-claims` — attaches an owner-scoped claim with proof level, confidence, visibility, context, ratings, and evidence refs.
- `GET /v0/places/:id/trust-summary` — returns a compact agent-readable proof summary for a saved place.
- `POST /v0/places/recommend-by-claims` — ranks owner-scoped saved places by verified claims and returns a retrieval receipt.
- `GET /v0/shared-place-links/:code` — public resolver for `/p/<shortCode>` App Clip/web previews.
- `POST /v0/shared-place-links` — authenticated creation of a short public place preview link from a sanitized `SharedPlaceData` payload.
- `GET /v0/workflows/place-recovery/runs` — authenticated list of SAV-E Place Recovery Agent workflow runs.
- `POST /v0/workflows/place-recovery/runs` — authenticated workflow run creation with internal credit reservation.
- `POST /v0/workflows/place-recovery/runs/:id/result` — records bounded worker/classifier result type and evidence tier.
- `POST /v0/workflows/place-recovery/runs/:id/decision` — records user confirm/edit/reject and creates an off-chain workflow receipt with credit settlement.

Collections, OpenAPI, `llms.txt`, external checkout, per-run on-chain receipts, and marketplace UI are intentionally out of scope for the first verified-claims/workflow-ledger slices.
