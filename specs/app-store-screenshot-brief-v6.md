# App Store Screenshot Principles Pass v6

- Paid user job / observed failure: Help travelers immediately understand that
  SAV-E turns shared place clues into private, user-confirmed place memory. The
  Atlas concept exports passed App Store dimensions but used generated art,
  padded canvases, and the same composition across iPhone and iPad.
- Acceptance criteria: Export five English screenshots from editable HTML and
  current SAV-E UI captures. Screen 1 leads with one clear value proposition;
  every screen carries one primary message; Screen 2 sells the result and adds
  a bounded human sharing cue; Screen 3 uses only truthful privacy/control trust
  signals; iPhone and iPad use native compositions without padding bars. Export
  opaque PNGs at 1242 x 2688 and 2064 x 2752.
- Failure fixture: Any whole-image regeneration, visible letterboxing, stretched
  or cropped app UI, fake rating/review/download claim, multi-message headline,
  overflow, wrong-size output, or alpha channel fails the task.
- Classification: App Store conversion and release-marketing maintenance; no
  new paid product capability.
- Demand proof / pricing hypothesis / first distribution: Founder requested a
  pass against Scrnsht Studio's seven conversion principles after reviewing the
  current set. The screenshots sell the free place-memory loop and introduce no
  paywall claim. First distribution is a later human-approved App Store Connect
  metadata update.
- Files and systems in scope: `specs/app-store-screenshot-board-v6.html`,
  `specs/export-app-store-screenshots-v6.mjs`, existing `real-ui-v5` captures,
  and generated v6 screenshot assets. Do not touch iOS product code, backend,
  auth, payment, deployment, or App Store Connect.
- Verification: Run `node specs/export-app-store-screenshots-v6.mjs`; inspect
  both contact sheets; verify five opaque PNGs per target at exact dimensions;
  scan the HTML for anti-slop violations; run `git diff --check`.
- Security and privacy: Use only current reviewer-demo UI, owned Memo artwork,
  and explicitly fictional share-copy. Do not include production accounts,
  private places, ratings, reviews, tokens, or secrets.
- Human approval still required: PR merge and any App Store Connect upload or
  release action.
