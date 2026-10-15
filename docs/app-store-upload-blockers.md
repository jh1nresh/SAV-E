# Savvy App Store upload blockers (2026-10-13)

[Documentation index](README.md) · [Launch checklist](../specs/launch-checklist.md) · [Listing copy](../specs/app-store-listing.md) · [Release commands](releasing.md)

In-repo readiness for **Savvy 1.0.0 (build 110)**. This is not an upload
receipt and does not authorize archive, TestFlight, or App Store Connect
actions. Owners: **Tim PR** (repo/docs/config this agent can change) vs
**founder Apple** (Apple ID, 2FA, ASC, signing, prices on the store).

Live tree facts used here:

- `MARKETING_VERSION` `1.0.0`, `CURRENT_PROJECT_VERSION` **110**, team
  `JC6858UYM9`, bundle `com.wanderly.app`
- ASC app `6769216556` name **Savvy: Save Places** (2026-08-24 read-back;
  version *Prepare for Submission*; last TestFlight seen **104** — stale vs 110)
- Local StoreKit monthly display price **4.99 → 6.99** in this change
- Annual remains **39.99** with a 3-day intro offer
- Product IDs: `com.wanderly.app.pro.monthly` / `com.wanderly.app.pro.annual`
- Privacy + support HTTP **200** on 2026-10-13:
  `https://sav-e-app.vercel.app/privacy` and `/support` (`/terms` also 200)

`SAVEPro.storekit` is local sandbox configuration. It does **not** set or
update the App Store Connect IAP price.

## Blocker table

| Category | What blocks archive → TestFlight → ASC submit **now** | Owner |
|---|---|---|
| Signing / certs | Xcode must be signed into the Apple ID that owns team `JC6858UYM9`. Automatic signing is already set in `project.yml`; a missing account, expired Apple Development/Distribution cert, or missing App Store profiles for `com.wanderly.app`, `.ShareExtension`, and `.Clip` still fails **Archive**. | **founder Apple** |
| Signing / certs | This repo cannot produce a signed archive. CI builds an unsigned generic-device candidate only. | **founder Apple** |
| ASC access | Safari / ASC login + 2FA. Agents must not touch the Apple account. | **founder Apple** |
| ASC access | Last visible TestFlight build at the 2026-08-24 read-back was `1.0.0 (104)`. In-repo is **110**. Nothing in git proves 110 was uploaded or processed. | **founder Apple** |
| ASC access | Version state was *Prepare for Submission*. Selecting build **110**, completing metadata, and **Submit for Review** are ASC clicks. | **founder Apple** |
| Legal | Privacy, support, and terms URLs resolve HTTP 200 (re-checked 2026-10-13). Not a live-URL blocker. | none (verified) |
| Legal | ASC **App Privacy** nutrition label, age-rating questionnaire (**4+**), and export-compliance answer (**No** — `ITSAppUsesNonExemptEncryption = false`) are still unconfirmed in ASC. | **founder Apple** |
| Legal | Any unpaid Apple developer, Paid Apps, tax, or banking agreement. Unknown from the repo; confirm before submit. | **founder Apple** |
| IAP product price | Local monthly display/config is now **$6.99**. ASC IAP price is a separate record and is **not** updated by this PR. | **founder Apple** (ASC) / **Tim PR** (local, this change) |
| IAP product price | Subscription products may not exist or may still be at a non-$6.99 monthly price. Create/edit `com.wanderly.app.pro.monthly` at **$6.99** and `com.wanderly.app.pro.annual` at **$39.99** with the 3-day trial on annual. | **founder Apple** |
| IAP product price | Launch posture stays **free download + purchase path later**. `purchasingIsAvailable` and `enforcementEnabled` remain `false`. Do not flip them in the same step as the first upload. Attaching IAPs to this version is a founder decision; if attached, listing copy must repeat subscription terms. | **founder Apple** |
| IAP product price | App Store Server Notifications v2 URL is still a human ASC registration (`POST /v0/notifications/apple`). Needed before live renewals; not required to archive a free 1.0 binary. | **founder Apple** |
| Metadata gaps | In-repo listing/checklist build numbers were stale (80 / 103 / 104). This change aligns them to **110**. ASC fields themselves are still empty-or-unverified from here. | **Tim PR** (docs) / **founder Apple** (ASC paste + screenshot upload) |
| Metadata gaps | v5 screenshot sets exist in `specs/app-store-screenshots/v5*` (and `design-assets/app-store`). They are not proof they are in the ASC slots. | **founder Apple** |
| Metadata gaps | Review Notes, a demo sign-in or Sample Place Clue path past auth, and categories Travel / Lifestyle. | **founder Apple** |
| CI | Unsigned Debug/Release CI is the code-readiness gate, not a signed IPA. This PR must stay green on its tip SHA. | **Tim PR** |
| CI | Passing PR CI is not a main-branch release-readiness receipt and is not an upload. | n/a |
| Secrets | `APP_STORE_CONNECT_API_KEY_PATH` / `_ID` / `_ISSUER_ID` are absent by design. Xcode Organizer upload does not need them in git. Do not commit or paste keys. | **founder Apple** (if using API-key upload) |
| Secrets | Production Gemini / Google Places / Privy / guest-session secrets live on Railway/Vercel, not in this tree. A missing backend key does not block the IPA, but it will fail review if core save/analyze is dead. | **founder Apple** |

## StoreKit monthly before / after

| Field | Before | After |
|---|---|---|
| File | `SAV-E/Resources/SAVEPro.storekit` | same |
| Product | `com.wanderly.app.pro.monthly` | same |
| `displayPrice` | **4.99** | **6.99** |
| Annual `displayPrice` | 39.99 | 39.99 (unchanged) |
| Paywall UI | `SaveProPaywallView` renders `product.displayPrice` from StoreKit; no hardcoded `$4.99` | same |
| App Store Connect | unknown / not this file | **founder must set monthly $6.99** |

## What is already true in the repo

- Bundle, team, and display name are the existing production identities. Do not
  change them.
- App icon, v5 screenshots, and Atlas Postcard tokens are in-tree.
- Release configuration compiles on CI (unsigned).
- Paywall, Restore, EULA, privacy, and cancellation copy exist; purchasing is
  gated off until ASC products exist.
- Support / privacy / terms pages are live.

## Founder clicks (exact)

Do these on the Apple ID that owns team `JC6858UYM9`. Do not hand the account
to an agent.

1. **Xcode → Settings → Accounts** — confirm the team appears.
2. Destination **Any iOS Device (arm64)** → **Product → Archive** (Release).
   If you re-archive after this, bump `CURRENT_PROJECT_VERSION` in
   `project.yml` above **110** and run `xcodegen generate`.
3. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
   Or export with `scripts/prepare-testflight-export-options.sh` using
   `APPLE_TEAM_ID=JC6858UYM9` (see [releasing.md](releasing.md)).
4. App Store Connect → app **6769216556** **Savvy: Save Places** → wait until
   build **1.0.0 (110)** is processed.
5. **Subscriptions** → product `com.wanderly.app.pro.monthly` → price
   **$6.99**. Annual `com.wanderly.app.pro.annual` → **$39.99** + 3-day free
   trial. Local StoreKit is not this step.
6. Paste listing fields from `specs/app-store-listing.md`. Upload the v5
   screenshot sets (not the older v3 names).
7. Fill App Privacy from the listing table; age rating **4+**; encryption
   **No**.
8. Review Notes: private place-memory app; confirm before Map Stamp; no public
   feed. Give a demo login **or** say the Sample Place Clue path works signed
   out.
9. Optional for this submit: attach IAP products only if they are Ready to
   Submit **and** the listing repeats subscription terms. Otherwise leave
   `purchasingIsAvailable` false and ship the free core.
10. Select processed build **110** → **Add for Review** → **Submit for Review**.
    Release **manually**.

Out of bounds for this packet: merge, ASC/TestFlight upload by an agent,
Apple 2FA, bundle ID changes, new brand, landing-page expansion.
