# Launch Without A Paywall

## Required brief

- Paid user job / observed failure: launch users should experience SAV-E's place-memory loop before being shown pricing or quota concepts; the Passport Memo Pro preview introduces monetization before demand is measured.
- Acceptance criteria: remove the Memo Pro entry, sheet, 20-assist preview, purchase/subscription copy, and iOS quota-preview request; keep Trips visibly labeled Beta without pricing language; keep authenticated backend AI usage metering non-enforcing and invisible; keep the current v5 App Store screenshots accurate.
- Failure fixture: a launch user can still find `profile.proPreview`, `paywall.root`, Memo Pro, purchase/subscription language, or a visible AI quota; or removing the UI disables backend Gemini usage events.
- Classification: launch-surface maintenance and monetization experiment rollback.
- Demand proof: there is not yet enough launch retention or repeated AI-usage evidence to justify a paywall. The pricing hypothesis is deferred until post-launch usage is observed.
- Pricing / paywall hypothesis: no hard or soft paywall at launch. Saved places, Review, Map Stamps, the private map, and Trips Beta remain accessible. Backend metering remains research-only and does not enforce a quota.
- First distribution format: the next human-approved TestFlight/App Store build, with no paywall surface.
- Files / systems in scope: Passport UI, Trips Beta copy, iOS quota-preview client/DTO, focused policy and UI tests, and superseded-spec notes. Backend routes, schema, usage events, StoreKit, entitlements, App Store Connect, and deployment are out of scope.
- Verification commands: focused `SAVEProductionConfigTests`, focused launch/paywall-absence UI test, unsigned generic iOS Simulator build, `git diff --check`, and a scoped source-string review.
- Security / privacy boundary: do not expose usage telemetry or add analytics payloads. Existing backend events remain owner-scoped and payload-free.
- Human approval still required: merge, production schema application, Railway deployment, signing, App Store Connect metadata, TestFlight upload, and release.
