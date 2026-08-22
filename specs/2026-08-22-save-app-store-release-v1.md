# SAV-E App Store Release v1

- **Paid user job / observed failure:** People cannot install SAV-E from the
  public App Store. The build still exposed TestFlight-only Pro copy, its
  documented support domain did not resolve, and users could not initiate
  account deletion in the app.
- **Acceptance criteria:** The public build is free, hides the unavailable Pro
  entry, exposes an authenticated and confirmed Delete Account action that
  removes owner-scoped backend data and the Privy identity, ships a live support
  page and privacy policy, and reaches App Store Connect with complete metadata.
- **Failure fixture:** A visible TestFlight-only claim, dead support/privacy URL,
  missing in-app account deletion, placeholder release secret, mismatched build
  number, failed CI, unprocessed upload, or incomplete review metadata blocks
  submission.
- **Classification:** Release and distribution maintenance.
- **Demand proof / pricing / distribution:** The founder explicitly requested a
  formal App Store launch. Version 1.0 is a free download; subscriptions remain
  unavailable and unenforced. The first distribution is the iOS App Store.
- **Files and systems in scope:** Profile settings, authenticated backend account
  deletion, Privy user deletion, local account cleanup, static support/privacy
  pages, listing/checklist metadata, iOS build number, Vercel, Railway, and App
  Store Connect.
- **Verification:** Backend tests and build, focused iOS tests, generic iOS
  Release build, signed archive inspection, live support/privacy HTTP checks,
  CI, upload processing, and App Store Connect read-back.
- **Security and privacy:** The server derives the account exclusively from the
  verified bearer token. The client sends no user ID. Profile deletion cascades
  owner-scoped data before Privy identity deletion. No credentials or private
  user records enter Git, logs, screenshots, or review notes.
- **Human approval:** The founder approved formal launch. Safari login and 2FA
  remain a human handoff. Any new Apple legal agreement must be accepted by the
  account holder. Release remains manual until App Review accepts the build.
