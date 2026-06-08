# SAV-E Railway Backend

Railway-hosted API for SAV-E mobile persistence. It replaces the previous Supabase Edge Function while preserving the iOS API contract.

## Environment

```bash
DATABASE_URL=postgresql://...
PRIVY_APP_ID=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
SAVE_GUEST_SESSION_SECRET=...
PORT=3000
GOOGLE_PLACES_API_KEY=...
SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION=false
SAVE_ENABLE_SERVER_OCR=false
```

Railway provides `DATABASE_URL` and `PORT`. Set the Privy values and a stable `SAVE_GUEST_SESSION_SECRET` on the backend service. If the guest secret is omitted, the backend generates an ephemeral process-local secret, which is only suitable for local development because guest sessions will expire on restart.

Source recovery can run with metadata and public search only. Set `GOOGLE_PLACES_API_KEY` to let the worker corroborate Review Candidates with Places address/coordinates. Set `SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION=true` to allow bounded public video fetch plus one keyframe sample, and set `SAVE_ENABLE_SERVER_OCR=true` only on workers that have `tesseract` installed. If these toggles are off or unavailable, recovery keeps the source as a cited clue instead of inventing place details.

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

Persistence routes accept either `Authorization: Bearer <Privy access token>` or `x-save-guest-token: <server-issued guest token>`.
Guest clients create a server-issued session with `POST /v0/guest-sessions`; the backend no longer trusts client-generated `guest_<uuid>` headers as authorization.

- `POST /v0/guest-sessions` — returns `guest_id`, `guest_token`, and `expires_at` for low-friction guest persistence.
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
- `POST /v0/places/recommend-by-claims` — ranks owner-scoped saved places by verified claims, stores a private recommendation-analysis receipt, and returns a retrieval receipt plus AgentShack-safe envelope.
- `POST /v0/recommendation-analysis-receipts` — stores an authenticated SAV-E recommendation-analysis receipt from bounded client request/output payloads and returns:
  - `id` (`string` UUID) — stored `recommendation_analysis_receipts.id`.
  - `envelope` (`object`) — AgentShack-safe receipt envelope projection with hashes, public summary, safe preference signals, evaluator verdict, settlement state, and private payload reference.
  - `full_payload_json` (`object|string`) — original SAV-E request/output payload stored in `private_payload`; deployments may return the JSON object or a serialized JSON string depending on database driver serialization.

  Example response:

  ```json
  {
    "id": "8f7f2f50-9c4a-48c1-8f55-8b4d821d7f0e",
    "envelope": {
      "product": "save",
      "receipt_type": "recommendation_analysis",
      "user_id": "user_123",
      "agent_id": "save-ios",
      "capability": "place_claim_recommendation",
      "input_hash": "7b6c4a0f3b4e5d0a1c2b3a4e5d6f708192a3b4c5d6e7f8091a2b3c4d5e6f7081",
      "output_hash": "6f4e2a0c3b1d5f708192a3b4c5d6e7f8091a2b3c4d5e6f70817b6c4a0f3b4e5d",
      "private_payload_ref": "save://receipts/recommendation_analysis/8f7f2f50-9c4a-48c1-8f55-8b4d821d7f0e",
      "public_summary": {
        "summary": "SAV-E analyzed owner-scoped saved places and kept public discovery separate.",
        "capability": "place_claim_recommendation",
        "result_count": 2,
        "saved_result_count": 1,
        "public_result_count": 1,
        "proof_level_min": "user_confirmed_place",
        "public_web_used": true
      },
      "preference_signals": ["coffee", "nearby", "proof_level:user_confirmed_place"],
      "evaluator_verdict": "pass",
      "settlement_state": "not_settled",
      "created_at": "2026-06-06T12:00:00.000Z"
    },
    "full_payload_json": {
      "receipt_type": "recommendation_analysis",
      "request": {
        "intent": "recommend nearby coffee",
        "constraints": ["nearby", "coffee"],
        "proof_level_min": "user_confirmed_place"
      },
      "output": {
        "public_fallback_used": true,
        "results": []
      }
    }
  }
  ```
- `GET /public/v0/cards/:id` — returns a public projection for a public-link/public-guide place with public/link-shared claims only.
- `POST /public/v0/claim-usage-receipts` — records bounded public usage receipts for public/link-shared claims.
- `POST /v0/claims/usage-receipts` — records authenticated owner-scoped usage receipts.
- `GET /v0/shared-place-links/:code` — public resolver for `/p/<shortCode>` App Clip/web previews.
- `POST /v0/shared-place-links` — authenticated creation of a short public place preview link from a sanitized `SharedPlaceData` payload.
- `GET /v0/workflows/place-recovery/runs` — authenticated list of SAV-E Place Recovery Agent workflow runs.
- `POST /v0/workflows/place-recovery/runs` — authenticated workflow run creation with internal credit reservation.
- `POST /v0/workflows/place-recovery/runs/:id/result` — records bounded worker/classifier result type and evidence tier.
- `POST /v0/workflows/place-recovery/runs/:id/decision` — records user confirm/edit/reject and creates an off-chain workflow receipt with credit settlement.

Public collections, OpenAPI, `llms.txt`, paid/API-key access, broad reputation graph exports, external checkout, per-run on-chain receipts, and marketplace UI are intentionally out of scope for the first verified-claims/workflow-ledger slices.
