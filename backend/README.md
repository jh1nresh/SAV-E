# Savvy Railway Backend

Railway-hosted API for Savvy mobile persistence. It replaces the previous Supabase Edge Function while preserving the iOS API contract.

## Environment

```bash
DATABASE_URL=postgresql://...
DATABASE_CA_CERT=
PGSSLMODE=require
PRIVY_APP_ID=...
PRIVY_APP_SECRET=...
PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----...'
SAVE_GUEST_SESSION_SECRET=...
SAVE_INTERNAL_AGENT_TOKEN=... # 32+ character server-to-server bearer token for private R8 pilot metrics
PORT=3000
GOOGLE_PLACES_API_KEY=...
AMAP_WEB_SERVICE_KEY=...
AMAP_INTERNATIONAL_WEB_SERVICE_KEY=...
AMAP_USAGE_AUTHORIZED=false
SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION=false
SAVE_ENABLE_SERVER_OCR=false
SAVE_SERVER_OCR_COMMAND=tesseract
SAVE_ENABLE_SERVER_ASR=false
SAVE_SERVER_ASR_COMMAND=whisper
SAVE_SERVER_ASR_MODEL=base
SAVE_EVIDENCE_RUBRIC_URL=
SAVE_EVIDENCE_RUBRIC_TOKEN=
SAVE_ENABLE_MAAT_PUBLIC_WEB=
GEMINI_API_KEY=
SAVE_GEMINI_PROXY_MODELS=gemini-3.5-flash,gemini-2.5-flash
SAVE_MAAT_GEMINI_MODEL=gemini-3.5-flash
YELP_API_KEY=
```

Railway provides `DATABASE_URL` and `PORT`. Set the Privy values and a stable `SAVE_GUEST_SESSION_SECRET` on the backend service. `PRIVY_APP_SECRET` enables server-side import of iMessage phone users into Privy; if omitted, Sendblue users still get Savvy backend profiles and verified channel bindings, but no Privy user is pre-created. If the guest secret is omitted, the backend generates an ephemeral process-local secret, which is only suitable for local development because guest sessions will expire on restart. External Postgres TLS verifies certificates by default; use a Railway internal URL, set `DATABASE_CA_CERT`, or set `PGSSLMODE` to a valid libpq value (`disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`). Prefer `require`. Modern libpq / `psql` reject `no-verify` (including `sslmode=no-verify` on pooler URLs). For a founder-owned apply, strip the query string and override that process only: `PGSSLMODE=require psql "${DATABASE_URL%%\?*}" …`. Do not change an already-working Railway service `PGSSLMODE`; Node `pg` still accepts the legacy `no-verify` token so a live service variable is not a rollout blocker.

`SAVE_INTERNAL_AGENT_TOKEN` gates `GET /internal/r8/pilot-metrics?days=30&limit=100`. Generate at least 32 random bytes with an OS cryptographic random generator, store the value only in Railway's secret manager and approved server-side agent runtime, and never ship it to the app or browser. The endpoint is read-only and returns cohort totals plus HMAC-pseudonymous per-user analysis and outcome counts; it never returns raw user IDs or recommendation payloads. If the token is missing or too short, the route fails closed with `503`; invalid bearer credentials return `401`. Successful reads emit a metadata-only audit log with the window, requested limit, and aggregate user counts. Rotating the token also rotates the v0 pseudonymous user references.

Source recovery can run with metadata and public search only. Set `GOOGLE_PLACES_API_KEY` to let the worker corroborate Review Candidates with Places address/coordinates. Set `SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION=true` to allow bounded public video fetch plus one keyframe sample, and set `SAVE_ENABLE_SERVER_OCR=true` only on workers that have `tesseract` installed. Set `SAVE_ENABLE_SERVER_ASR=true` only on workers that have a local Whisper-compatible CLI available through `SAVE_SERVER_ASR_COMMAND`; transcripts are attached as cited evidence and never used to invent address/coordinates. Set `SAVE_EVIDENCE_RUBRIC_URL` to an HTTPS public rubric service endpoint when you want an external LLM rubric; the worker sends a bounded projection of metadata/candidate/search/media text, validates the response schema, blocks redirects/private hosts, and falls back to the deterministic rubric when unavailable. If these toggles are off or unavailable, recovery keeps the source as a cited clue instead of inventing place details.

Authenticated China place resolution stays server-side. `AMAP_WEB_SERVICE_KEY` enables the domestic GCJ-02 fallback only when `AMAP_USAGE_AUTHORIZED=true`; Savvy preserves that coordinate system and opens the exact Amap place instead of treating it as a MapKit pin. `AMAP_INTERNATIONAL_WEB_SERVICE_KEY` is optional and must be set only after Amap enables overseas Web Service permission; its WGS84 results can render on the unified MapKit surface. Never put either key in the iOS bundle.

Ma'at restaurant detail enrichment is deterministic unless the caller opts into public web. When `GET /v0/places/:id/maat-analysis?includePublicWeb=true` is called, the backend first uses structured sources before asking the model: `GOOGLE_PLACES_API_KEY` can fill Google rating, price level, parking options, reservable status, dine-in/takeout traits, and Google source links; `YELP_API_KEY` can optionally add Yelp score, price, categories, and bounded review excerpts through the official Yelp API. When `GEMINI_API_KEY` or `GOOGLE_GEMINI_API_KEY` is configured, the backend then asks Gemini with public web search for remaining restaurant details such as dishes, parking, reservation tips, average cost, and common negative reviews. The same backend key powers authenticated `/v0/llm/gemini-generate-content` proxy calls from the iOS app so Gemini keys do not ship in the app bundle. Set `SAVE_ENABLE_MAAT_PUBLIC_WEB=false` only when this enrichment must be disabled. The prompt only sends bounded place metadata and non-private claim summaries; raw private evidence is never included. If structured sources or the model are unavailable, the route falls back to the selected-place evidence analysis and marks `analysis_receipt.structured_source_status` / `analysis_receipt.public_web_status`.

## Local

```bash
npm install
npm run build
npm run check:source-recovery
npm run start
```

Apply schema / pending SQL (see **Deploy checklist** below and `sql/README.md`):

```bash
# From repository root, new empty database only:
psql "$DATABASE_URL" -f backend/sql/schema.sql

# From backend/: pending additive file (dry-read, then apply). Founder-owned.
cd backend
./scripts/apply-sql.sh friend-ratings.sql
./scripts/apply-sql.sh friend-ratings.sql --apply
```

Production source recovery readiness:

```bash
cd backend
npm run build
npm run check:source-recovery
curl "$RAILWAY_PUBLIC_DOMAIN/health/source-recovery"
```

`npm start` builds the TypeScript backend and runs `check:source-recovery` before boot. The check stays green when OCR, ASR, and external rubric are disabled. It fails when an enabled OCR/ASR adapter is missing its executable or when `SAVE_EVIDENCE_RUBRIC_URL` is not an HTTPS public URL. Railway also uses `/health/source-recovery` as the deployment healthcheck, so source-recovery adapter misconfiguration blocks rollout instead of silently falling back in production.

## Deploy checklist

Merge does not migrate. The backend does not auto-apply SQL on boot.
Production `psql` apply is founder-owned. Do not treat a merged PR as
authorization to migrate or deploy.

1. Apply pending SQL against the target database (local first; production only
   with founder approval). Order:
   - `sql/schema.sql` — new empty database only
   - pending additive files, oldest first: `sql/analysis-usage.sql` (if those
     tables are not already present), then `sql/friend-ratings.sql`, then any
     later file listed in `sql/README.md`
   - `friend-ratings.sql` creates `idx_places_id_user_id` if missing before the
     composite FK, so a database that already has `places` but lacks that index
     does not fail the way the #241 prod apply did
   - From `backend/`: dry-read, then apply: `./scripts/apply-sql.sh friend-ratings.sql`
     then `./scripts/apply-sql.sh friend-ratings.sql --apply`
   - If `psql` rejects `sslmode=no-verify` (from `backend/`; known prod URL
     only carries that query param):
     `PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -1 -f sql/friend-ratings.sql`
     Use the helper when the URL has other libpq query params — it drops
     `sslmode` only.
2. Verify tables (read-only). Expect `t|t|t`:

   ```bash
   PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -tAc \
     "select to_regclass('public.idx_places_id_user_id') is not null,
             to_regclass('public.friend_restaurant_ratings') is not null,
             to_regclass('public.friend_rating_saves') is not null;"
   ```

3. Railway-deploy this backend (separate human approval; not this repository
   change and not `npm start`).
4. Distribute the matching iOS build (separate human approval).

Do not re-apply SQL to production from a docs/hygiene PR. Do not enable
analysis spend limits from this checklist. Do not rewrite a live Railway
`PGSSLMODE` if the Node service is already running.

## Social-analysis accounting and admission

Same deploy order as the checklist above: apply `backend/sql/analysis-usage.sql`
(or the complete `schema.sql` on a new database), verify tables, deploy this
backend, then distribute the matching iOS build. The new iOS import requires
`/v0/analysis`; missing tables/routes fail closed and preserve the local source.
The additive migration does not change existing places or decisions. Roll back
application code with enforcement off; do not drop operational tables or user
records as rollback.

Each active social import/refinement creates an owner-scoped UUID with
`POST /v0/analysis {"id":"UUID"}`. Its Google searches use
`POST /v0/analysis/:id/places`; Gemini and China requests carry
`x-save-analysis-id`. Recovery accepts the same header or `analysis_id` body
field. `POST /v0/analysis/:id/client-events` accepts only bounded operation,
outcome, duration and UUID fields; the server ignores client cost/token claims.
`POST /v0/analysis/:id/finish` links owned capture IDs and an outcome. Owner-only
`GET /v0/analysis/:id` returns attempt/token totals, known cost estimates, explicit
unknowns, and confirmed/saved candidate counts. Client telemetry is unverified;
missing or truncated client receipts, unfinished sessions and unknown costs make
`cost_complete` false. Operational events never contain URLs, prompts, captions,
queries, candidate evidence or saved/shared notes.

Costs use gross USD retail estimates (`retail-usd-2026-09-13`), excluding free
allowances, discounts, tax and infrastructure. Google legacy Text Search uses
$32/1,000 requests; Gemini 3.5 Flash text input/output uses $1.50/$9 per million,
and 2.5 Flash $0.30/$2.50. Cached input uses $0.15/$0.03 respectively. Output
includes thinking tokens; absent/inconsistent usage stays unknown. Sources:
[Google pricing](https://developers.google.com/maps/billing-and-pricing/pricing),
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing?authuser=3),
[thinking/output limits](https://ai.google.dev/gemini-api/docs/generate-content/thinking).
External rubric and China pricing remain unknown. Local OCR/ASR, Apple search,
HTML lookup and media downloads have zero variable external-provider estimate;
that does not mean zero compute/network cost. Failed requests retain an unknown
billable outcome. Do not treat these estimates as actual invoices or divide only
successful requests by confirmations: include failed analyses, retries and
unconfirmed imports when calculating cost per saved place from a time cohort.
A capture can link several analyses; deduplicate confirmations across the cohort.

Enforcement is **off by default**. Activation and amounts require a separate
approved configuration change. Setting `SAVE_ANALYSIS_LIMITS_ENABLED=true`
requires all five nonnegative integer settings (zero is an explicit stop):

- `SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT`: sessions started per account per UTC day.
- `SAVE_ANALYSIS_REQUEST_LIMIT`: server operation attempts per analysis.
- `SAVE_ANALYSIS_BUDGET_MICROS`: reserved USD micros per analysis.
- `SAVE_ANALYSIS_ACCOUNT_DAILY_BUDGET_MICROS`: per account per UTC day.
- `SAVE_ANALYSIS_GLOBAL_DAILY_BUDGET_MICROS`: all scoped analyses per UTC day.

One USD is 1,000,000 micros. Admission serializes reservations across processes
in PostgreSQL before dispatch, with a bounded SQL timeout. A paid request keeps
the larger of its reservation and known estimate; failures/abandonment never
refund a reservation. Text-only Gemini requests bound input and output (including
thinking); unknown prices or incomplete enabled configuration deny further
provider work. Invalid/missing analysis IDs cannot bypass enabled Gemini/China
gates. This is an operational spend guard, not a purchased user entitlement;
internal retries are metered attempts, not paid credits. It does not cap legacy
apps using embedded provider keys, ordinary direct map searches, unrelated
backend routes, or infrastructure. Provider key restrictions and a provider-side
budget policy remain separate release decisions.

Recovery coalesces identical owner/capture/input/workflow work and reuses
successful results for five minutes. Failed work is retryable. Cross-process
leases last ten minutes and fence stale result publication; a crash after an
external request cannot guarantee exactly-once provider billing. Candidate
writes are transactionally deduplicated, and reuse reloads current candidate
states so saved/rejected/deleted candidates are not resurrected. A new analysis
reusing the same result links the capture and reports `reused_from_analysis_id`;
provider charges remain on the original analysis. Cache rows hold private
recovery output and expire for reuse; they are removed with the owning account
or capture, not automatically purged at the reuse deadline.

Focused PostgreSQL/HTTP fixtures require `SAVE_ANALYSIS_TEST_DATABASE_URL` pointing
to the disposable `save_analysis_fixture` database on a private socket under
`/tmp/save-analysis-completion/`. Apply the schema there, build, then run
`node --test dist/analysisUsage.test.js` and `node --test dist/analysisApi.test.js`
sequentially from `backend/`. The API fixture substitutes every provider fetch;
no real provider credentials or traffic are used. Without that variable these
database tests explicitly skip; ordinary `npm run validate` still runs the
pure accounting, recovery, parser and transport boundary tests.

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
- `POST /v0/exports/trek-kml` — exports 1–100 explicitly selected, owner-scoped Map Stamps as a private/no-store KML attachment compatible with [TREK](https://github.com/mauriceboe/TREK). The request body is `{ "place_ids": ["<uuid>"] }`; the export includes only place ID, name, address, category, status, and coordinates, and excludes notes, source URLs, photos, and evidence.
- `GET /profile`
- `PATCH /profile`
- `GET /v0/usage/quota` — returns the authenticated user's current UTC-month AI-assist usage preview. The v0 policy is a non-enforcing TestFlight hypothesis (`20` monthly units, warning at `15`); missing telemetry schema returns `metering_available=false` and never blocks Beta access.
- `POST /memory/captures/:id/search-recovery` — runs public search recovery for source-only captures and writes search-derived results back as review-only place candidates.
- `POST /v0/places/:id/related-sources` — Privy bearer-only and owner-rate-limited; re-verifies an owned Google-confirmed public venue through a bounded cache, then searches a bounded public index for likely same-place Instagram, TikTok, YouTube, Xiaohongshu, Douyin, Threads, or X links. The owner-scoped response contains candidate-only sources plus per-platform coverage and a private retrieval receipt; it performs no place, claim, Trip, or source-edge writes.
- `GET /v0/places/:id/verified-claims` — returns owner-scoped place claims; raw evidence refs are omitted unless `includePrivateEvidence=true`.
- `POST /v0/places/:id/verified-claims` — attaches an owner-scoped claim with proof level, confidence, visibility, context, ratings, and evidence refs.
- `GET /v0/places/:id/trust-summary` — returns a compact agent-readable proof summary for a saved place.
- `GET /v0/places/:id/maat-analysis` — returns selected-place Ma'at restaurant details. Add `includePublicWeb=true` to opt into Google Places / optional Yelp structured enrichment plus env-gated Gemini public-web enrichment; model output only fills gaps and the receipt records whether structured source, public web, and model enrichment were used.
- `POST /v0/places/recommend-by-claims` — ranks owner-scoped saved places by verified claims, stores a private recommendation-analysis receipt, and returns a retrieval receipt plus AgentShack-safe envelope.
- `POST /v0/recommendation-analysis-receipts` — stores an authenticated Savvy recommendation-analysis receipt from bounded client request/output payloads and returns:
  - `id` (`string` UUID) — stored `recommendation_analysis_receipts.id`.
  - `envelope` (`object`) — AgentShack-safe receipt envelope projection with hashes, public summary, safe preference signals, evaluator verdict, settlement state, and private payload reference.
  - `full_payload_json` (`object|string`) — original Savvy request/output payload stored in `private_payload`; deployments may return the JSON object or a serialized JSON string depending on database driver serialization.

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
        "summary": "Savvy analyzed owner-scoped saved places and kept public discovery separate.",
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
- `GET /internal/r8/pilot-metrics?days=30&limit=100` — internal bearer-authenticated, agent-callable R8 pilot metrics. Technical evaluator verdicts and latest linked `explicit_user` outcome counts are reported separately; evaluator/deterministic outcomes cannot become user success, user identity is an HMAC pseudonym, and private payload fields are excluded.
- `GET /public/v0/cards/:id` — returns a public projection for a public-link/public-guide place with public/link-shared claims only.
- `POST /public/v0/claim-usage-receipts` — records bounded public usage receipts for public/link-shared claims.
- `POST /v0/claims/usage-receipts` — records authenticated owner-scoped usage receipts.
- `GET /v0/shared-place-links/:code` — public resolver for `/p/<shortCode>` App Clip/web previews.
- `POST /v0/shared-place-links` — authenticated creation of a short public place preview link from a sanitized `SharedPlaceData` payload.
- `GET /v0/workflows/place-recovery/runs` — authenticated list of Savvy Place Recovery Agent workflow runs.
- `GET /v0/workflows/place-recovery/runs/summary` — authenticated aggregate counts for runs, Instagram reels, source URL runs, analysis receipts, decision receipts, and user-feedback receipts.
- `POST /v0/workflows/place-recovery/runs` — authenticated workflow run creation with internal credit reservation.
- `POST /v0/workflows/place-recovery/runs/:id/result` — records bounded worker/classifier result type and evidence tier, creates an off-chain **analysis** workflow receipt (`receipt_type=analysis`) with `workflow_version`, `operator_id`, `requester_id`, `agent_id`, optional `job_id`, `model_provenance`, input/output hashes, permission snapshot, tool trace refs, latency/cost/failure fields, then points `workflow_runs.receipt_id` at that receipt.
- `POST /v0/workflows/place-recovery/runs/:id/decision` — records user confirm/edit/reject and creates an off-chain **decision** workflow receipt with credit settlement plus `user_feedback_action`, `quality_delta`, and `reputation_delta`.

To move selected Savvy Map Stamps into TREK without copying either product's private data model, request the export with the same Privy or guest authorization used by other persistence routes:

```bash
curl -X POST "$SAVE_API_URL/v0/exports/trek-kml" \
  -H "Authorization: Bearer $SAVE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"place_ids":["11111111-1111-4111-8111-111111111111"]}' \
  --output save-map-stamps.kml
```

Import `save-map-stamps.kml` from TREK's planner file-import surface. Savvy remains the place-memory source of truth; TREK owns downstream itinerary editing and route planning.

Public collections, OpenAPI, `llms.txt`, paid/API-key access, broad reputation graph exports, external checkout, per-run on-chain receipts, and marketplace UI are intentionally out of scope for the first verified-claims/workflow-ledger slices.
