# Trips Beta and Paywall Boundary

## Required brief

- Paid user job / observed failure: SAV-E needs an honest path toward paid AI usage without blocking the core saved-place memory loop or presenting an unstable trip planner as a finished paid feature.
- Classification: product-loop boundary and payment-readiness UI.
- Acceptance criteria:
  - The app does not show a paywall at launch.
  - The first Map Stamp and core Capture, Review, Saves, and private-map flows remain free.
  - Trips is visibly labeled Beta and says it is free during Beta.
  - Passport exposes an optional Memo Pro preview that separates free features from planned Pro features.
  - The preview has no subscribe, trial, purchase, or entitlement-changing action.
- Failure fixtures:
  - A paywall appears before the user saves a place.
  - Trips appears production-ready or requires payment during Beta.
  - The preview implies a transaction can occur without an App Store product and verified backend entitlement path.
- Demand proof: current product evidence supports the saved-place memory loop; trip planning is still being stabilized. Previous pricing notes recommend testing a soft paywall only after users receive a useful saved-place artifact.
- Pricing / paywall hypothesis: keep activation and Trips Beta free, preview Pro from Passport, and later charge for bounded high-cost AI usage only after usage and retention evidence exists.
- First distribution format: TestFlight observation of saved-place activation and optional Pro-preview interest; no purchase conversion test in this slice.
- Files and systems in scope: shared product policy constants, Atlas Trips presentation, Passport Pro preview, unit policy test, and focused UI test. StoreKit, App Store Connect products, backend ledgers, receipts, and entitlements are out of scope.
- Verification:
  - Generic iOS Simulator Debug build with code signing disabled.
  - Unit assertions for launch, first-save, Trips Beta, and purchase-availability policy.
  - Focused UI assertions and screenshots for Trips Beta and the non-transactional Pro preview.
  - Diff scan confirming no StoreKit product or purchase path was added.
- Security and privacy boundary: no payment details, transaction identifiers, receipts, entitlement writes, new analytics, or user-place data leave the existing systems.
- Human approval still required: enabling purchases, creating App Store products, choosing price and trial terms, adding backend transaction verification, merging, signing, TestFlight/App Store upload, and production deployment.
