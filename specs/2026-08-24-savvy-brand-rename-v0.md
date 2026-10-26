# Savvy brand rename v0

## Required brief

- **Paid user job / observed failure:** A user should see one coherent, memorable product name everywhere. The current `SAV-E` spelling is harder to say and appears inconsistently across the app, extensions, sharing copy, web support pages, and Apple metadata.
- **Acceptance criteria:** The installed app, App Clip, Share Extension, iMessage surface, App Intents, user-facing copy, support/privacy pages, and current product documentation use `Savvy`. Home shows the `Savvy` wordmark. App Store Connect is prepared for `Savvy: Save Places`, with pure `Savvy` preferred only if Apple confirms it is available. Existing installs, private data, links, subscriptions, and server receipts remain compatible.
- **Failure fixture:** A scoped brand scan finds a user-facing `SAV-E` string in current runtime/product surfaces, or the built app reports a display name other than `Savvy`. A build/test failure, changed bundle identifier, changed App Group, changed StoreKit product ID, or removed legacy deep-link route also fails the slice.
- **Classification:** Maintenance / brand migration. No new product loop.
- **Demand proof:** Direct founder naming decision on 2026-08-24. There is no separate market-demand proof for the rename.
- **Pricing / paywall hypothesis:** No pricing or entitlement change. Existing `com.wanderly.app.pro.*` product identifiers remain intact; user-facing Pro naming becomes `Savvy Pro`.
- **First distribution format:** A reviewable stacked PR, then the next TestFlight/App Store version after human review. On-device name: `Savvy`. App Store title: `Savvy: Save Places` unless `Savvy` is confirmed available in App Store Connect.
- **Files and systems in scope:** iOS app and extension display names; current runtime copy and accessibility labels; App Intents; StoreKit reference display text; current web support/privacy/share copy; current backend-generated user-facing copy; current README/design/product contracts; App Store rename handoff/metadata.
- **Out of scope / compatibility identifiers:** Xcode project directory and internal target/module/type names; repository path; `com.wanderly.*` bundle IDs, App Groups, Sign in with Apple identity, StoreKit product IDs, associated-domain hosts, database/API keys, and existing `wanderly://` deep links. These are implementation identities, not the public brand.
- **Verification commands:** scoped brand scan; `git diff --check`; backend/web tests affected by copy; generic iOS Simulator Debug build with shared DerivedData; targeted brand/UI tests; one headless runtime screenshot only if static/build checks pass and storage gate allows it.
- **Security and privacy boundary:** No user data migration and no auth, entitlement, subscription, receipt-verification, associated-domain, or server ownership change. Public wording can change; private identifiers and secrets cannot.
- **Human approval still required:** PR merge; signing/archive/upload; selecting a build; App Review/TestFlight submission; release. The user explicitly authorized an Apple-facing rename, but any account agreement, legal/tax action, unavailable-name fallback beyond `Savvy: Save Places`, or release action remains human-controlled.

## Apple naming boundary

Apple allows the localized App Store name to be edited while the app/version status permits it. The product name is limited to 30 characters and can be used by one app per localization. `Savvy: Save Places` is the safe first submission title; the installed binary remains `Savvy`.

The existing App Store record and bundle ID must remain the same so this ships as an update instead of a new app. App Clip, Share Extension, App Group, StoreKit product IDs, receipt validation, and legacy links continue using their existing technical identifiers.

## Subsequent StoreKit migration — PR #292

The August brand-only baseline above preserved `com.wanderly.app.pro.annual`
and `com.wanderly.app.pro.monthly`. PR #292 separately changes the reserved
identifiers to `savvy.pro.annual` and `savvy.pro.monthly`, respectively. This is
an explicit product-ID migration, outside the original brand-only scope; it
does not retroactively change that baseline or its failure fixture.

Purchasing remains disabled (`purchasingIsAvailable = false`). This source
change does not establish that the new products exist in App Store Connect,
activate purchases, or prove legacy subscription/receipt compatibility. Before
activating or releasing purchases, verify the App Store Connect product setup
and whether any legacy products have transactions. If legacy entitlements
exist, preserve and test their restore and server-receipt recognition before
activation; renaming source constants alone is not a migration of subscribers.
Bundle IDs, App Groups, account identities and legacy deep links remain intact.
