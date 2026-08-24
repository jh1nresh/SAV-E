# App Store Screenshot Refresh v5

- Paid user job / observed failure: Help travelers understand that Savvy turns loose place clues into private, confirmed place memory. The existing App Store screenshots no longer matched the live product UI.
- Acceptance criteria: Ship five English screenshots built from current app captures for Home, Capture, Review, Map, and Passport; keep Trips out of the primary promise while it remains Beta; export opaque PNGs at 1260×2736, 1242×2688, and 2048×2732; verify the focused screenshot rail passes.
- Failure fixture: A Capture screenshot with the keyboard covering the action, a Passport screenshot showing reviewer-auth errors, a missing Review candidate, a cropped composition, or any wrong-size/alpha output fails the task.
- Classification: Conversion loop and release marketing maintenance; no new paid product capability.
- Demand proof / pricing hypothesis / first distribution: Founder-observed mismatch between the store listing and current app. The screenshots sell the free place-memory loop; no paywall claim is introduced. First distribution is the next human-approved App Store Connect metadata update.
- Scope: `SaveCaptureFlowView`, reviewer-demo profile behavior, focused UI screenshot automation, the HTML board/exporter, and generated screenshot assets under `specs/app-store-screenshots/`.
- Verification: Run `specs/capture-app-screenshots.sh`; run `node specs/export-app-store-screenshots.mjs`; inspect contact sheets; verify pixel dimensions, opacity, and `git diff --check`.
- Security and privacy: Use deterministic reviewer-demo fixtures only. Do not include production accounts, tokens, private user places, or secrets in screenshots or committed assets.
- Human approval still required: PR merge and any App Store Connect upload or release action.
