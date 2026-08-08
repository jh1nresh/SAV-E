# SAV-E Verified Account Reference Rotation

## Required brief

- Paid user job / observed failure: a returning user using the original Google
  account is blocked by “This isn’t your saved SAV-E account” after the backend
  account-reference secret changed.
- Root cause: the device still holds the previous opaque HMAC reference in
  Keychain, while `/v0/account-status` returns a reference derived with the
  current secret. The client treats every mismatch as a different person.
- Acceptance criteria:
  - a previous reference opens the local vault only when the authenticated
    backend proves that it belongs to the same resolved profile;
  - a successful proof replaces the Keychain value with the current reference;
  - an unrelated, malformed, duplicated, or unproved reference remains blocked;
  - no raw profile identifier, account secret, or local SAV-E data is exposed,
    cleared, or copied.
- Failure fixtures: same profile + previous secret, different profile + previous
  secret, malformed reference, duplicate header, missing prior secret, and
  profile-binding recovery states.
- Classification: auth maintenance bug fix.
- Demand proof: real-device screenshot from 2026-08-07 showing the returning
  user trapped on the different-account recovery screen.
- Pricing / paywall: N/A; this restores existing account access.
- First distribution format: TestFlight after human-approved merge, backend
  configuration, backend deploy, and iOS upload.

## Scope and security boundary

- The app sends its existing opaque Keychain reference in
  `X-SAVE-Account-Ref` on the authenticated, no-store account-status request.
- The backend compares that reference only against HMACs for the authenticated
  profile, using the current secret and explicitly retained previous secrets.
- `SAVE_MY_SAVES_SECRET` is automatically treated as the previous reference
  secret when a dedicated `SAVE_ACCOUNT_REF_SECRET` replaced that fallback.
- Additional rotations may be listed in
  `SAVE_ACCOUNT_REF_PREVIOUS_SECRETS` as comma-separated secret values.
- The response returns only `current`, `previous`, or `none`; it never returns
  prior references, secrets, Privy subjects, or profile IDs.
- The existing Keychain service and account name remain unchanged so the old
  reference is available for proof. Changing the Keychain domain is rejected:
  the local vault is not account-scoped, so forgetting the binding could admit
  a genuinely different account.
- Out of scope: changing Privy identities, clearing or repartitioning the local
  vault, profile merging, release, or production configuration mutation.
- Human approval remains required for production environment changes, backend
  deploy, merge, signing, TestFlight upload, and release.

## Xcode context receipt

- Product/repo: `/Users/jhinresh/projects/sav-e`
- Platform/project/scheme/target: iOS / `SAV-E.xcodeproj` / `SAV-E` / `SAVE`
- Deployment target: iOS 17.0; Swift 6
- Verification tier: host logic plus build-only
- Destination: `generic/platform=iOS Simulator`; runtime simulator N/A
- Canonical DerivedData: `~/Library/Developer/Xcode/DerivedData/SAVE-Codex`
- Selected route: `swift-xcode-workflow`, direct generic `xcodebuild`
- Build constraint: an unrelated Xcode owner was detected by the storage
  lifecycle harness, so no competing local Xcode build may start. CI is the
  build/XCTest checker until that owner exits.
- Local verification: focused Swift host fixture passed 12/12; backend build and
  Node test suite passed 353/353; `git diff --check` passed. The completed diff
  security scan found no reportable issue. Secret-pattern scanning is part of
  the final pre-commit gate.
