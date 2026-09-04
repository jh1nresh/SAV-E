# Launch: Purchase Path Ready, Trigger Later

## Required brief

- Paid user job / observed failure: founders need a launch monetization posture that can charge later without training users on a Day-1 hard wall, and without locking the free place-memory loop. Common “add paywall later and you never monetize” advice was being misread as “show a launch paywall.”
- Acceptance criteria: App Store listing ships as a **free download**; StoreKit + server grant path remain wired; no automatic launch/onboarding paywall; paywall may open only after a confirmed Map Stamp, and only from (a) AI-assist refusal once enforcement is on, or (b) Passport → Savvy Pro; core map / Stamp / search / trip editing stay free forever; client observes purchases only — server grants.
- Failure fixture: launch auto-paywall; paywall before first Map Stamp; Passport Pro opens with zero Stamps; `enforcementEnabled` flipped while Ask / model-quota surfaces are still removed; client-side tier grant; Home/Map/Origin day-1 upgrade banners.
- Classification: product-boundary lock (docs + trigger-policy alignment). Not Slice 3 price/enforcement flip.
- Demand proof: place-memory loop is the shippable value today; Ask / trip-generation were temporarily removed, so the reactive AI refusal trigger is dormant until those surfaces return.
- Pricing / paywall hypothesis: **purchase path early, interruption late.** Freemium with locked AI outcome. Weekly-anchor annual layout is paywall *chrome* after the sheet exists — separate follow-up, not a trigger change.
- First distribution format: next human-approved TestFlight / App Store build marketed as free; Pro purchasable from Passport only after ASC products exist and `purchasingIsAvailable` is flipped; enforcement stays off until a real model-quota refusal path is live.
- Files / systems in scope: this decision record, launch checklist alignment, `SAVEProAccessPolicy` posture comments, `SaveEntitlementStore` trigger helpers, Passport Pro entry gate, focused entitlement tests.
- Verification: focused entitlement / production-config tests; `git diff --check`.
- Security / privacy: no client grant; no new telemetry payloads.
- Human approval still required: App Store Connect subscription products and prices (founder + Elon), attaching IAPs to the build, flipping `purchasingIsAvailable`, flipping `enforcementEnabled`, merge, signing, TestFlight / App Store release.

## Locked posture

```text
App Store price: Free
Purchase plumbing: ready (StoreKit + /v0/entitlements/apple)
Trigger: late
  1) AI assist refused (enforcement on) → reactive sheet
  2) Passport → Savvy Pro → passive sheet
Never: launch / onboarding wall, pre-Stamp wall, day-1 tab banners
```

### Flag sequence (do not collapse)

1. Ship free core with flags at defaults: `purchasingIsAvailable = false`, `enforcementEnabled = false`.
2. Human creates ASC products (reserved IDs in `SAVEProAccessPolicy.ProductID`) and attaches them to the build.
3. Flip **`purchasingIsAvailable = true` only** → Passport can buy; still no forced wall; AI still fail-open.
4. Restore Ask (or equivalent model-metered surface) + server refusal.
5. Flip **`enforcementEnabled = true`** (client + server) in one PR after usage evidence — Slice 3 in `2026-08-19-save-pro-entitlement-remaining-work.md`.
6. Optional later: soft 20% nudge; weekly-anchor paywall layout spec.

## Relationship to older specs

- Supersedes the launch *marketing* reading of `launch-without-paywall.md` that implied “no Pro surface at all.” Trigger rules from that doc (no launch wall; memory loop free) **remain**.
- Continues `2026-08-19-save-pro-entitlement-and-paywall-v0.md` Slice 1–2 wiring; does **not** start Slice 3 price/enforcement choices.
- Explicitly rejects onboarding hard-paywall patterns as Savvy’s Day-1 trigger policy.
- Flag names in code: `SAVEProAccessPolicy.purchasingIsAvailable`, `SAVEProAccessPolicy.enforcementEnabled`, `SAVEProAccessPolicy.showsAutomaticLaunchPaywall`.
- Product IDs live in `SAVEProAccessPolicy.ProductID` (reserved ahead of ASC).
- Slice 3 checklist: `2026-08-19-save-pro-entitlement-remaining-work.md`.

## Out of scope

- Choosing dollar prices or trial length
- Enabling enforcement
- Restoring Ask / trip generation UI
- Paywall weekly-anchor layout
- Railway / ASC console actions by the agent
