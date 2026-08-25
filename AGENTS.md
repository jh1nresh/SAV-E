# Savvy Agent Contract

Savvy turns saved-place clues into user-confirmed place memory and trip
planning. R8 may supply evidence, but it does not write Savvy user truth.
SLL-R commerce is a later handoff and is outside this repository's default
scope.

## Required Brief

Before editing, record:

- paid user job or observed failure
- acceptance criteria and failure fixture
- feature, loop, or maintenance classification
- demand proof, pricing/paywall hypothesis, and first distribution format
- files and systems in scope
- verification commands
- security and privacy boundary
- actions that still require human approval

If those fields are missing, produce a clarification brief instead of guessing.

## Engineering Loop

```text
scoped brief or issue
-> isolated branch/worktree
-> smallest reviewable patch
-> local verification
-> pull request
-> CI maker/checker feedback
-> human review and merge
-> release-readiness receipt
-> human-controlled distribution
```

- Trigger: one scoped brief or GitHub issue.
- Durable state: issue/PR plus the CI release-readiness artifact.
- Input boundary: only task-relevant repo files and redacted fixtures.
- Maker: the engineering agent on an isolated branch.
- Checker: deterministic CI plus independent human review.
- Feedback: failed build, test, fixture, audit, or review finding.
- Artifact: one atomic PR and, after main passes, one
  `save-release-readiness.json`.
- Convergence: acceptance criteria pass, CI is green, and no unrelated files
  changed.
- Human approval: merge, production secrets/schema changes, Railway or Vercel
  deployment changes, signing, App Store Connect, and TestFlight release.
- Stop: missing product boundary, auth/payment ambiguity, private-data risk,
  unavailable credentials, failing checks after three repair attempts, or less
  than 10 GiB free before a runtime gate.

## Verification

For ordinary iOS edits, compile without booting a simulator:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/SAVE-Codex" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Boot one headless simulator only for focused XCTest or UI evidence. Reuse the
same DerivedData root, then shut down and delete the device before reporting.
CI is the canonical full checker for the native app, backend, web contracts,
and evidence rubric.

## Release Boundary

The main-branch CI builds an unsigned generic-device Release configuration with
a synthetic non-secret Google key and emits a release-readiness receipt only
after every required job passes. The binary is not uploaded as an artifact.
That receipt is evidence of code readiness, not a signed archive or deployment.
Never run `railway up`, `vercel --prod`, archive/upload to App Store Connect, or
publish a TestFlight build without explicit user approval at action time.
