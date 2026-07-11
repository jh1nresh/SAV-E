# SAV-E Full Repo Security Audit - 2026-07-09

## Scope

- Repo: `/Users/jhinresh/projects/wanderly-current`
- Branch: `ios-design-stamp-moment`
- Revision reviewed: `54727ec48e132d00822e3e2a49878a52764705ef`
- Mode: Codex Security standard scan plus targeted high-risk review across backend, iOS, App Clip, Supabase Edge Functions, dependency/config surfaces, and source-recovery fetchers.
- Deep profile note: official Codex Security deep scan was not completed because local agent depth is configured as `1`; the deep profile preflight requires depth `>= 2`.
- Dirty baseline preserved: existing screenshot/design changes were present before this audit and were not modified.

## Verdict

Public-test blockers are concentrated in the iMessage/SMS bot boundary:

1. Require webhook authentication before any Sendblue state mutation.
2. Stop logging raw phone payloads, source links, replies, and tokenized My SAV-E links.
3. Remove Gemini API keys from client bundles and enforce that in Release builds.

The source-recovery URL fetch path was reviewed specifically for SSRF. The current fetch helpers block private hosts/redirects and bound response sizes, so no confirmed SSRF finding was kept.

## Findings

### F-1 HIGH - Sendblue webhook accepts spoofed sender identity

Evidence:

- `POST /v0/sendblue/webhook` is registered before normal auth in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:662).
- `handleSendblueWebhook` reads JSON and processes it without verifying a Sendblue signature in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:920).
- The bot trusts caller-supplied `from_number`, `number`, `from`, or `fromNumber` in [backend/src/sendblueBot.ts](/Users/jhinresh/projects/wanderly-current/backend/src/sendblueBot.ts:1836).
- A first-time sender is auto-created as a verified iMessage binding in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:764).
- `verifySignature` exists in [backend/src/sendblueBot.ts](/Users/jhinresh/projects/wanderly-current/backend/src/sendblueBot.ts:2430), but route wiring was not found.

Impact:

An internet caller that can reach the backend can POST a fake inbound Sendblue payload for an arbitrary phone number. That can poison saved places, verified visits, reviews, remembered location, and trigger order/recurring flows for the claimed number. Direct data exfiltration is limited because normal replies go to the claimed phone number, but state integrity and user trust are broken.

Fix:

Read the raw request body, verify Sendblue HMAC/shared-secret before parsing or processing, require `SENDBLUE_SIGNING_SECRET` in production, and reject unsigned requests. Add a regression test that fake `from_number` payloads do not call `processSendblueInbound` or mutate memory.

### F-2 HIGH - Raw private message payloads and tokenized replies are logged

Evidence:

- Full inbound webhook payload is logged in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:928).
- Sender and text are logged in [backend/src/sendblueBot.ts](/Users/jhinresh/projects/wanderly-current/backend/src/sendblueBot.ts:1969).
- Replies are logged in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:958).
- My SAV-E tokens are stable HMAC links without expiry in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:798).
- Those links expose saved places, visits, and reviews in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:824).

Impact:

Production logs can retain phone numbers, source URLs, receipt text, review text, generated replies, and private `/my/<token>` links outside the normal app data-access boundary. Anyone with log access could inspect a user's place graph if a tokenized reply was logged.

Fix:

Replace raw logs with structured redacted logs: hashed phone, event type, body size, and result code only. Never log raw payloads, message text, source URLs, replies, or `/my/` tokens. Add TTL/revocation to My SAV-E tokens before relying on them as private links.

### F-3 HIGH - Current local iOS build can bundle a Gemini API key

Evidence:

- README policy says Gemini should remain a backend secret, but [project.yml](/Users/jhinresh/projects/wanderly-current/project.yml:34) adds `SAV-E/Resources/Secrets.plist` as an app resource and [project.yml](/Users/jhinresh/projects/wanderly-current/project.yml:143) adds the share-extension `Secrets.plist` as a resource.
- The prebuild scripts create those local files from templates if missing in [project.yml](/Users/jhinresh/projects/wanderly-current/project.yml:38) and [project.yml](/Users/jhinresh/projects/wanderly-current/project.yml:147).
- The shared transport allows a client Gemini fallback from `GEMINI_API_KEY` when enabled in [SAV-EShared/SAVEProductionConfig.swift](/Users/jhinresh/projects/wanderly-current/SAV-EShared/SAVEProductionConfig.swift:27).
- The actual local `Secrets.plist` files are ignored, not tracked, by `.gitignore`, which prevents a git leak but does not prevent bundling into archives.

Impact:

If a local or CI archive contains `GEMINI_API_KEY` in the ignored `Secrets.plist`, the app bundle can expose a server-paid Gemini key. This is not a committed-secret leak, but it is a release-build secret exposure risk.

Fix:

Remove Gemini keys from all client `Secrets.plist` files. Make the backend proxy the only Gemini path for Release/TestFlight. Add a Release prebuild guard that fails if `GEMINI_API_KEY` exists in any app or extension plist. Rotate the key if a build containing it was shipped.

### F-4 MEDIUM - Public social/referral projections can expose raw source fields

Evidence:

- Public referrals route before auth in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:652).
- Social/referral queries select `p.*` in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:2507), [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:2551), and [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:2593).
- `formatSocialPlace` returns `placeFields`, including `note`, `source_url`, `source_image_url`, and photos from [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:316), via [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:2631).
- Public claim cards explicitly state `source_policy: "raw sources private"` in [backend/src/placeClaims.ts](/Users/jhinresh/projects/wanderly-current/backend/src/placeClaims.ts:148).

Impact:

Places that are opted into friend/public guide surfaces can leak saved notes or raw source URLs through social/referral projections, even though public cards summarize proof instead of exposing raw sources.

Fix:

Create a dedicated public/social place projection. Do not reuse `placeFields`; include only name, coarse address/city, category, rating, public claims, and public image fields that are explicitly safe.

### F-5 MEDIUM - Public claim-usage receipts can inflate reputation counts

Evidence:

- `POST /public/v0/claim-usage-receipts` is reachable without auth in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:1048).
- The handler inserts caller-supplied usage receipts in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:1101).
- Public cards expose `claim_id` in [backend/src/placeClaims.ts](/Users/jhinresh/projects/wanderly-current/backend/src/placeClaims.ts:72).
- Usage and accepted counts feed reputation output in [backend/src/placeClaims.ts](/Users/jhinresh/projects/wanderly-current/backend/src/placeClaims.ts:360).

Impact:

Anyone who knows a public/link-shared claim ID can inflate or skew usage/accepted counts for public reputation. This does not expose private data, but it damages trust metrics.

Fix:

Require a signed client/session proof, rate-limit by IP/session/claim, dedupe by stable actor, and exclude unauthenticated receipts from high-trust reputation summaries.

### F-6 MEDIUM - Guest sessions can use the Gemini proxy

Evidence:

- Unauthenticated callers can mint guest sessions in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:658).
- Guest tokens are accepted by `resolveUserId` in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:3088).
- The Gemini proxy forwards caller-controlled content using the server key in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:1345).

Impact:

Anyone can consume backend Gemini quota/cost through the public backend when `GEMINI_API_KEY` is configured. Request size, response size, model allowlist, and redirect blocking reduce blast radius, but this is still a paid capability exposed to anonymous users.

Fix:

Gate proxy access by authenticated users or tightly scoped first-run sessions, add per-token/IP rate limits, and restrict guest prompts to specific app workflows instead of a generic `generateContent` proxy.

### F-7 MEDIUM - Workflow result endpoint is owner-authenticated, not worker-authenticated

Evidence:

- `POST /v0/workflows/place-recovery/runs/:runId/result` only verifies run ownership before accepting result writes in [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:1882).
- The normalizer accepts caller-supplied result type, evidence tier, evidence refs, candidate refs, agent id, and model provenance in [backend/src/workflowContracts.ts](/Users/jhinresh/projects/wanderly-current/backend/src/workflowContracts.ts:139).

Impact:

A normal authenticated or guest owner can forge worker analysis results for their own run. Cross-user writes are blocked, so this is mostly a receipt/provenance integrity problem.

Fix:

Require a worker-only credential or signed worker result envelope for `/result`, and keep user-facing review decisions separate from worker provenance receipts.

### F-8 LOW/MEDIUM - Supabase legacy Edge Function can cross-reference other users' place IDs if deployed

Evidence:

- The Supabase Edge Function uses a service-role client and verifies Privy manually before routing.
- Worker review found trip creation accepts `trip_stops.place_id` values without proving that the referenced place belongs to the caller.

Impact:

If this Edge Function is deployed and used, a valid user can attach another user's private place ID to their own trip stop and use FK behavior as a weak existence oracle. Railway backend may have superseded this path, so production reachability is uncertain.

Fix:

Either retire the Edge Function from production or enforce ownership/visibility checks on every referenced `place_id` before insert.

### F-9 LOW/MEDIUM - `PGSSLMODE=no-verify` disables database TLS verification

Evidence:

- Semgrep flagged [backend/src/server.ts](/Users/jhinresh/projects/wanderly-current/backend/src/server.ts:3386), which returns `{ rejectUnauthorized: false }` when `PGSSLMODE=no-verify`.
- Backend docs describe this as a temporary accepted environment.

Impact:

If production sets `PGSSLMODE=no-verify`, database traffic is encrypted but not authenticated against the server certificate.

Fix:

Disallow `no-verify` in production and require `DATABASE_CA_CERT` or a provider-verified TLS mode.

## Dependency Audit

- `backend`: `npm audit --json` found one low `esbuild` advisory through dev tooling (`tsx`). No confirmed production request path.
- `services/evidence-rubric`: `npm audit --json` found zero advisories.
- `save-rn`: `npm audit --json` found `form-data` high, `undici` high/moderate/low, `js-yaml` moderate, and `@babel/core` low advisories. Most appear tied to Expo/build/test or transitive SDK tooling; production reachability was not proven.

## Counterevidence / No Finding Kept

- Tracked secret scan did not find committed real secret files. `.env.local` and real `Secrets.plist` files are ignored.
- Source-recovery fetch helpers use safe URL checks, DNS/private-IP rejection, manual redirect handling, bounded body reads, and tests for private-host redirects. No confirmed SSRF was kept.
- Evidence-rubric service requires bearer auth and caps request body size.
- My SAV-E HTML escapes fields and restricts source links to `http`/`https`.
- Token comparisons reviewed use `timingSafeEqual` where expected.

## Verification Commands

```bash
npm audit --json
semgrep --config p/secrets --config p/javascript --config p/typescript --config p/swift --config p/owasp-top-ten --error --json --exclude node_modules --exclude build --exclude '*.xcarchive'
git ls-files .env.local .env.example backend/.env.example SAV-E/Resources/Secrets.plist SAV-E/Resources/Secrets.plist.template SAV-EShareExtension/Secrets.plist SAV-EShareExtension/Secrets.plist.template
git check-ignore -v .env.local SAV-E/Resources/Secrets.plist SAV-EShareExtension/Secrets.plist
```

## Recommended Next Slices

1. Fix Sendblue webhook signature verification and redact logs.
2. Remove client Gemini key path from Release/TestFlight and add build guards.
3. Patch public/social projections and claim-usage receipt trust rules.
4. Decide whether Supabase `save-api` is live; retire or patch ownership checks.
5. Add anonymous Gemini proxy rate limits or remove generic guest access.
