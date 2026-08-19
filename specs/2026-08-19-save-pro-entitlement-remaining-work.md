# SAV-E Pro Entitlement — Remaining Work

> Continues `2026-08-19-save-pro-entitlement-and-paywall-v0.md`.
> Slices 1 and 2 are merged (#140, #141); the client/server wiring is in
> review (#142). This spec covers everything still open, in dependency order.

## Where the work actually stands

Shipped and verified:

- client purchase path, entitlement store, reactive paywall (#140)
- Apple JWS verification pinned to Apple Root CA - G3, `subscription_entitlements`
  table, tier-aware allowance (#141)
- client posts the signed transaction to `/v0/entitlements/apple` (#142, in review)

The system can verify a purchase and remember it. It cannot yet **charge** for
anything, because no App Store Connect products exist, and it cannot **refuse**
anything, because `enforcementEnabled` is false in both layers.

Two properties must survive every item below:

1. The client may observe a purchase; only the server may grant one.
2. Nothing refuses a user until Slice 3 explicitly flips enforcement.

---

## A. Production schema + deploy — DONE 2026-08-19

Applied and verified. Recorded here because the instruction originally written
in this spec was wrong and would have been risky.

**The mistake:** this spec first said to run `psql -f backend/sql/schema.sql`.
That file is 1558 lines; re-running it in production would replay 8 backfill
`UPDATE`s, 3 constraint rebuilds, and 1 column type change — a large blast
radius for adding one table.

**What was actually done:** extracted only the `subscription_entitlements` DDL
into a fragment, scanned it for destructive statements (0 found), and applied it
in a single transaction with `ON_ERROR_STOP=1`.

```bash
# read-only check first
railway run --service save-backend -- bash -c \
  'PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -tAc \
   "select to_regclass('"'"'public.subscription_entitlements'"'"') is not null;"'
# -> f   (confirmed missing)

railway run --service save-backend -- bash -c \
  'PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -1 \
   -f /tmp/save-entitlements-migration.sql'
# -> CREATE TABLE / CREATE INDEX / CREATE TRIGGER
```

Note: the Supabase pooler URL carries `sslmode=no-verify`, which `psql` rejects.
Strip the query string and set `PGSSLMODE=require` instead.

Verified in production: table present with the unique key on
`original_transaction_id`, FK cascade to `profiles`, both check constraints, and
the `updated_at` trigger. The tier-resolution query the server runs returns
empty without error.

Deployed commit `490e723` via `railway up`; deployment reached SUCCESS and
`/health/source-recovery` returns 200.

### A trap worth recording

Auth runs **before** routing, so a nonexistent path returns the same 401 as a
real one. Probing `/v0/entitlements/apple` without credentials proves nothing
about whether the route exists — the verification step originally written in
this spec was therefore useless, and briefly led to the wrong conclusion that
the route was already deployed. Confirm deployment by checking the deployed
commit and the compiled bundle, not by curling an authenticated route.

---

## B. App Store Server Notifications v2 — DONE 2026-08-19 (PR #143)

Implemented in `backend/src/appleNotifications.ts` plus the
`POST /v0/notifications/apple` route. 16 new tests; 413/413 backend tests pass.

Design notes worth keeping:

- Apple's payload is two layers of JWS — the outer notification, and
  `data.signedTransactionInfo` nested inside it. Both are verified against the
  same pinned chain from `proEntitlement.ts`; no second verification path.
- The route is matched *before* the bearer-token gate, because Apple has no user
  session. The signature is the authentication.
- The handler updates, never inserts. A test asserts the absence of
  `insert into` in that function: if a webhook could insert, a forged delivery
  could mint entitlement against an arbitrary `user_id`.
- An unverified payload returns 400, not 200 — acknowledging unsigned input
  would invite replay. Everything *after* successful verification returns 200 so
  Apple stops retrying.
- `DID_FAIL_TO_RENEW` is ignored rather than revoked: a billing retry is not yet
  a cancellation, and Apple sends `EXPIRED` / `GRACE_PERIOD_EXPIRED` if it
  ultimately fails. Revoking early would cut off a paying user over a transient
  card decline.
- `DID_CHANGE_RENEWAL_STATUS` keeps access until the period ends. The user paid
  for it.

Remaining human steps before this does anything:

1. Register the URL in App Store Connect → App Information → App Store Server
   Notifications (Production and Sandbox URLs, **V2**).
2. Deploy.
3. Sandbox proof: trigger a renewal and confirm the row updates **without the
   app being opened**. Until that is observed, treat this as untested against
   real Apple traffic — every test so far uses a locally generated chain.

---

## C. Slice 3 — enable revenue

**Do not start until the entry gate is met.** Every item here is a judgment
call that needs real data, and an agent must not choose any of them alone.

### Entry gate

- [ ] 100+ real installs
- [ ] one full calendar month of `ai_usage_events`
- [ ] A and B shipped and observed stable

The current `freeMonthlyLimitUnits: 20` was chosen before any distribution
existed. It is a placeholder, not a limit. Enabling enforcement against it would
refuse users based on a guess.

### C1. Read the distribution first

```sql
-- monthly AI assists per active user
select
  count(*)                                          as users,
  percentile_cont(0.50) within group (order by units) as p50,
  percentile_cont(0.75) within group (order by units) as p75,
  percentile_cont(0.90) within group (order by units) as p90,
  percentile_cont(0.99) within group (order by units) as p99,
  max(units)                                        as max_units
from (
  select user_id, sum(units) as units
  from ai_usage_events
  where created_at >= date_trunc('month', now() - interval '1 month')
    and created_at <  date_trunc('month', now())
  group by user_id
) per_user;
```

Also needed before choosing a number:

- what fraction of users ever produce a confirmed Map Stamp (the value proof)
- what fraction reach any AI assist at all
- cost per assist, so the Pro price covers p90 usage with margin

Write the answers into a decision note. A number with no distribution behind it
repeats the current mistake.

### C2. Choose the allowance

Principle: the free tier should let a genuine user experience the loop
repeatedly and still hit the wall while they are getting value — not on day one,
and not never. Somewhere near p50–p75 of engaged users is the usual shape, but
the data decides.

Update `proEntitlementPolicy.freeMonthlyLimitUnits` and
`betaUsageQuotaPolicy.monthlyLimitUnits` together, or they will drift.

### C3. App Store Connect — human-only

- create the subscription group and both products with the IDs already reserved
  in `SAVEProAccessPolicy.ProductID`
- set price and the 3-day trial on annual
- fill localized display names and descriptions
- attach products to the submitted build, state `Ready to Submit`
- confirm `SAVEProAccessPolicy.Legal.termsURL` and `privacyURL` resolve to real
  published pages — they are currently unverified placeholders and are a
  guaranteed rejection if dead

### C4. Flip enforcement

One change, both layers, same PR:

- `SAVEProAccessPolicy.enforcementEnabled = true`
- `SAVEProAccessPolicy.purchasingIsAvailable = true`
- backend `enforced: true` in the quota preview
- the Gemini proxy must actually refuse when the server says exhausted; today
  nothing calls the gate on the server side

That last point is real remaining work, not a flag flip. The server currently
*reports* a quota; it does not enforce one. Enforcement means the proxy checks
the caller's tier and monthly usage before forwarding to Gemini, and returns a
structured 402/429 the client can turn into the paywall.

Update the guard test in `SAVEProductionConfigTests` in the same change — it
currently asserts enforcement is off, and that assertion is the intended
tripwire.

### C5. Submission checklist

Carried from the v0 spec because it is cheap to lose:

- Restore Purchases present and functional
- EULA + privacy links on the paywall itself
- price, duration, auto-renewal terms visible before purchase
- closable sheet
- App Store description repeats the subscription terms
- screenshots do not show a paywall as the first screen

---

## Dependency order

```text
A (schema + deploy)          <- DONE 2026-08-19
B (ASSN webhook)             <- DONE, PR #143; needs App Store Connect URL + deploy
  -> #142 merge
  -> [entry gate: 100 installs + 1 month data]
  -> C1 read distribution
  -> C2 choose allowance
  -> C3 App Store Connect    <- human-only
  -> C4 flip enforcement + implement server-side refusal
  -> C5 submit
```

## What stays true throughout

- No paywall at launch, on foreground, or before a confirmed Map Stamp.
- Saved places, Map Stamps, the private map, notebooks, search, and
  deterministic parsing stay free and unmetered forever.
- The client never grants entitlement.
- Every failure path fails open until C4, and fails *closed on verification*
  always.

## Human approval required

Production schema, Railway deploy, App Store Connect products, prices, trial
terms, the webhook URL, enabling enforcement, merge, signing, TestFlight and
App Store submission.
