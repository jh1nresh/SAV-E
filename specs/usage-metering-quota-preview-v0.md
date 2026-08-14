# Usage Metering + Quota Preview v0

## Required brief

- Paid user job / observed failure: SAV-E has a Memo Pro preview but no reliable, server-authoritative measurement of expensive AI usage. Any paywall or quota decision made now would therefore be arbitrary.
- Acceptance criteria: successful authenticated Gemini proxy responses record one monthly AI-assist unit; upstream or transport failures record zero units; parser/cache-only work records nothing; `GET /v0/usage/quota` returns an authenticated monthly preview with a 20-unit hypothesis, warning state at 15, and `enforced=false`; the iOS Memo Pro sheet shows the preview without a purchase action or feature lock; a missing production table fails open.
- Failure fixture: a Gemini upstream 5xx or network failure must not reduce the displayed remaining units, and missing usage schema must not break Gemini or block the Beta.
- Classification: feature slice for the monetization learning loop.
- Demand proof: TestFlight users are already exercising capture, source recovery, Ask SAV-E, and Trips Beta; the current Pro sheet communicates future higher AI limits but cannot yet show actual usage.
- Pricing / paywall hypothesis: measure a 20-AI-assist monthly preview and warn at 15. This is a research hypothesis, not a purchased entitlement or a final launch price. Saved places, Map Stamps, the private map, and Trips Beta remain free.
- First distribution format: TestFlight-only soft preview inside Passport > Memo Pro preview.
- Files / systems in scope: backend usage policy, schema, authenticated Gemini proxy metering, quota summary route, backend tests, iOS API DTO/client, Memo Pro preview UI, focused tests, and documentation.
- Verification commands: `npm test` and `npm run build` in `backend/`; focused Swift package tests; unsigned generic iOS Simulator build; one focused headless UI test if runtime resources and disk gates are available.
- Security / privacy boundary: only user ID, operation kind, model, outcome, status, latency, and aggregate token counts may be stored. Never store prompts, generated text, source URLs, place names, private notes, or API keys in usage telemetry. The server decides units; the client cannot grant or charge credits.
- Human approval still required: production schema application, Railway deployment, StoreKit products, prices, entitlements, enforcement, App Store Connect changes, TestFlight upload, merge, and release.

## Out of scope

- StoreKit 2, subscriptions, trials, receipts, entitlement verification, and hard quota enforcement.
- Charging for saved places, Map Stamps, private-map access, deterministic parsing, cache hits, or Trips Beta.
- Reusing the workflow `credit_ledger`, whose units represent internal workflow settlement rather than user billing.
