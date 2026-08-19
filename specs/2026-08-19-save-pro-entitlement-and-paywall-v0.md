# SAV-E Pro Entitlement and Paywall v0

> Supersedes the monetization rollback in `launch-without-paywall.md` (PR #131)
> and promotes `usage-metering-quota-preview-v0.md` from research-only metering
> to a purchasable entitlement. Metering stays server-authoritative; this spec
> adds the purchase and entitlement path around it, not a new meter.

## Why now

The repo is at TestFlight build 101, not yet on the App Store. Two facts drive
the timing:

- StoreKit products and subscription metadata must clear App Store review with
  the first submission. Adding them after 1.0 is a second review cycle and
  subscription first-submissions are commonly rejected on 3.1.1 / metadata.
- TestFlight in-app purchases run in the StoreKit sandbox, so they are free.
  TestFlight can prove that the purchase path works and that people tap it. It
  cannot prove willingness to pay.

Conclusion: build the full purchase path now so it ships with 1.0, but do not
tune price, trial length, or conversion copy from TestFlight numbers.

## Required brief

- Paid user job / observed failure: users who rely on Ask SAV-E, link parsing,
  and trip generation consume unbounded Gemini spend, while the product has no
  way to charge for the expensive part of the loop. Backend metering already
  records the cost but cannot act on it.
- Classification: feature slice for the monetization loop, plus a deliberate
  regrade of the PR #131 no-paywall guard.
- Demand proof: `ai_usage_events` already records per-user monthly AI-assist
  units in production. That is the demand instrument. The 20-unit hypothesis in
  `betaUsageQuotaPolicy` was set without distribution data and must be re-read
  against real usage before enforcement is enabled.
- Pricing / paywall hypothesis: freemium with a locked outcome. The saved-place
  memory loop stays free forever; AI assists past a monthly allowance require
  SAV-E Pro. Annual is the primary offer with a 3-day trial, monthly is the
  control. Exact prices are a human decision at Slice 3.
- First distribution format: before/after screen recording of a pasted social
  link becoming a confirmed Map Stamp, then Ask SAV-E answering from saved
  places. The paywall is not the hook; the memory artifact is.
- Verification: focused Swift package tests, unsigned generic iOS Simulator
  build, `npm test` and `npm run build` in `backend/`, and a StoreKit
  configuration file for local purchase simulation.
- Security / privacy boundary: the client never grants entitlement. Only signed
  Apple transactions verified server-side may write entitlement state. Usage
  telemetry keeps its existing payload-free shape: no prompts, generated text,
  source URLs, place names, or notes.
- Human approval still required: App Store Connect product creation, price and
  trial terms, enabling enforcement, production schema application, Railway
  deployment, signing, TestFlight upload, merge, and release.

## Free / paid boundary

The moat is accumulated place memory. Locking memory would stop the asset from
compounding and would make export/deletion obligations worse. Lock the marginal
AI cost instead.

Free forever, unmetered:

- unlimited saved places, Source Clues, Review Candidates, Map Stamps
- the private map, notebooks, place detail, search over saved places
- deterministic parsing, cache hits, and share-extension capture that resolves
  without an AI call
- viewing and editing any trip that already exists

SAV-E Pro, metered as AI assists:

- Ask SAV-E answers that require a model call
- trip generation and gap-fill suggestions
- social-link parsing that falls through to the Gemini proxy
- batch Google Maps saved-list import beyond the free allowance

One AI assist equals one successful `gemini_generate_content` unit as already
defined by `buildGeminiUsageEvent`. Upstream and transport failures stay at zero
units. This is the existing contract and does not change.

## Trigger policy

The paywall is never the first screen. Order is fixed:

```text
first session
-> capture one link or place
-> confirmed Map Stamp (the value proof)
-> free AI assists continue until the allowance is consumed
-> paywall at the moment an AI assist is refused
```

Two entry points only:

1. Reactive: an AI assist is requested with no remaining allowance. The sheet
   explains what was blocked and what stays free.
2. Passive: a Pro row in Passport, always reachable, never interruptive.

Forbidden: launch paywall, paywall before the first Map Stamp, paywall on app
foreground, and any full-screen interstitial the user did not cause.

## Server-authoritative entitlement

The client may read entitlement and may present it. It may not decide it.

```text
StoreKit 2 purchase
-> signed JWS transaction
-> POST /v0/entitlements/apple  (backend verifies with Apple)
-> subscription_entitlements row (owner-scoped)
-> GET /v0/usage/quota returns tier + allowance
-> client renders state
```

Failure modes and required behavior:

- Backend unreachable: fail open. The user keeps working at the free allowance;
  never strand a paying user behind a network error.
- Entitlement table missing: fail open, same as the existing
  `isMissingRelationError` path for `ai_usage_events`.
- Client claims Pro without a verified row: ignored. The server response is the
  only truth.

## Slices

### Slice 1 — client entitlement + purchase + paywall (this change)

In scope: `SAVEProAccessPolicy` reinstated with an enforcement flag defaulting
to off, a StoreKit 2 service handling products / purchase / restore /
transaction updates, an entitlement store, the paywall view, the trigger policy,
a StoreKit configuration file for local simulation, and the regrade of the
PR #131 guard test.

Out of scope: backend verification, App Store Connect products, real prices,
enforcement.

Acceptance criteria:

- `SAVEProAccessPolicy.enforcementEnabled` is `false` and no code path blocks an
  AI assist while it is false.
- No paywall can present before a confirmed Map Stamp exists.
- The paywall shows Restore Purchases, an EULA link, a privacy policy link, the
  renewal period, and the cancellation path.
- Purchase and restore work against the StoreKit configuration file.
- The entitlement store never writes Pro from a client-only signal.
- Tests assert the trigger order and the absence of a launch paywall.

Failure fixtures:

- a paywall presents on first launch or before the first Map Stamp
- an AI assist is refused while `enforcementEnabled` is false
- the paywall lacks Restore, EULA, privacy, or renewal terms
- entitlement is granted from a local flag with no verified transaction

### Slice 2 — backend verification and enforcement plumbing

`subscription_entitlements` table, Apple JWS verification, App Store Server
Notifications v2 for renewal and cancellation, tier-aware allowance in
`buildUsageQuotaPreview`, and enforcement still defaulting to off.

### Slice 3 — enable enforcement and ship

Read real usage distribution, choose the allowance from that distribution rather
than the current 20-unit placeholder, create App Store Connect products, set
price and trial, flip enforcement, submit.

Do not start Slice 3 until at least 100 real installs and one full month of
`ai_usage_events` exist.

## App Store review checklist for subscriptions

Carried forward to Slice 3, listed here so it is not rediscovered late:

- Restore Purchases control present and functional
- EULA and privacy policy links on the paywall itself
- price, duration, and auto-renewal terms visible before purchase
- subscription products attached to the submitted build and marked Ready to
  Submit
- App Store description repeats the subscription terms
- no dark-pattern dismissal; the sheet must be closable
