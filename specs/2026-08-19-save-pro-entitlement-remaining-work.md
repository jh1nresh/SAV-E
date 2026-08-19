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

## A. Production schema + deploy — human-only, blocks everything

Owner: JhiNResH. No agent may run these.

`subscription_entitlements` exists in `backend/sql/schema.sql` but has not been
applied to production. Until it is, `/v0/entitlements/apple` returns 503 and the
quota endpoint reports every caller as `free`.

Order matters: schema first, then deploy. A deployed backend hitting a missing
table logs warnings on every request.

```bash
# 1. inspect first — never apply blind
psql "$DATABASE_URL" -c "\d subscription_entitlements"

# 2. apply (idempotent: create table if not exists)
psql "$DATABASE_URL" -f backend/sql/schema.sql

# 3. deploy
railway up
```

Verification after deploy:

```bash
# expect 200 with tier:"free" for a normal user
curl -H "Authorization: Bearer $TOKEN" https://<api>/v0/usage/quota

# expect 400 "Transaction could not be verified", NOT 503
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"signed_transaction":"garbage"}' https://<api>/v0/entitlements/apple
```

A 503 on the second call means the schema did not apply. A 500 means something
else broke and the deploy should be rolled back.

Acceptance: quota returns `tier` for authenticated callers; the entitlement
route rejects a bad transaction with 400 rather than 503; no new error rate on
existing routes.

---

## B. App Store Server Notifications v2 — the real gap

Without this, entitlement only refreshes when the client posts a transaction. A
user who cancels, is refunded, or whose renewal fails keeps their stored
`active` row until the app happens to send something.

Time-based tier resolution (#141) is what makes this gap *safe* rather than
dangerous — an expired row resolves to `free` on read regardless of its stored
status. So this is a correctness and latency fix, not a security hole. It does
not block launch, but it should land before enforcement.

### Scope

New route `POST /v0/notifications/apple`, unauthenticated by session but
authenticated by signature.

```text
Apple -> signedPayload (JWS)
      -> verify with the SAME pinned chain path as proEntitlement.ts
      -> decode notificationType + subtype + renewalInfo/transactionInfo
      -> update subscription_entitlements by original_transaction_id
      -> 200 OK
```

Reuse `verifyCertificateChain` and the fingerprint pin. Do not write a second
verification path — a weaker one here would undo the strength of the first.

Notification types that must change stored state:

| Type | Effect |
|---|---|
| `DID_RENEW` | extend `expires_at`, status `active` |
| `EXPIRED` | status `expired` |
| `DID_CHANGE_RENEWAL_STATUS` (auto-renew off) | keep `active`, do not extend |
| `REVOKE` | status `revoked` |
| `REFUND` | status `revoked` |
| `GRACE_PERIOD_EXPIRED` | status `expired` |

Everything else: log the type, return 200, change nothing. An unrecognized
notification must not throw and must not be retried forever by Apple.

### Hard requirements

- **Always return 200** once the signature verifies, even if the row is unknown.
  Apple retries non-2xx for days; a 500 loop on one stale transaction is worse
  than a no-op.
- **Idempotent.** Apple can deliver the same notification more than once. Key on
  `original_transaction_id` and never append.
- A notification for an `original_transaction_id` with no matching row is a
  no-op, not an insert. Entitlement is only ever created by an authenticated
  user posting their own transaction; a webhook must not be able to conjure a
  row against an arbitrary user.
- Store no new fields beyond what the table already holds.

### Verification

Extend `proEntitlement.test.ts` using the existing openssl-generated chain:

- a validly signed `DID_RENEW` extends expiry
- a validly signed `REFUND` sets `revoked`
- an unpinned-root notification is rejected
- a duplicate delivery is a no-op (idempotency)
- an unknown `notificationType` returns 200 and changes nothing
- an unknown `original_transaction_id` does not create a row

Sandbox proof before calling it done: trigger a real renewal in the App Store
sandbox and confirm the row updated without the app being opened.

Human approval: adding the webhook URL in App Store Connect, deploy.

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
A (schema + deploy)          <- blocks everything, human-only
  -> #142 merge
  -> B (ASSN webhook)        <- before enforcement, not before launch
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
