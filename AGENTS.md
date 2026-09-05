# Savvy Agent Contract

Savvy turns saved-place clues into user-confirmed place memory and trip
planning. R8 may supply evidence, but it does not write Savvy user truth.
SLL-R commerce is a later handoff and is outside this repository's default
scope.

## Required Brief

For feature, product-state or commercial changes, record:

- paid user job or observed failure
- acceptance criteria and failure fixture
- feature, loop, or maintenance classification
- demand proof, pricing/paywall hypothesis, and first distribution format
- files and systems in scope
- verification commands
- security and privacy boundary
- actions that still require human approval

For bounded maintenance, record the observed problem, scope, acceptance criteria,
relevant verifier, applicable security/privacy boundaries and actions requiring
human approval. Commercial fields may be `N/A`; mark other boundaries `N/A`
only when they are inapplicable. Use context already available rather than
asking for it again. Clarify only a missing decision that
changes correctness, product behavior, privacy, payment or authority.

## Design Reference

Read the relevant `DESIGN.md` sections and theme tokens for a user-visible
change. Read the full design contract for a new direction or cross-surface state
change. A copy or spacing fix does not require rereading the whole document.
`DESIGN.md` remains the source of truth for intent, state language and platform
boundary.

Token authority order, most authoritative first:

1. `SAV-E/Extensions/Color+Theme.swift` — owns the actual palette values. Code
   wins over any hex written in Markdown.
2. `DESIGN.md` — owns intent, naming, state language, and what is not allowed.
3. `design-assets/` — accepted examples (`app-store/`, `logo-exploration/`,
   `social/`). Reference them; do not treat them as tokens.

For a bounded implementation detail, follow the nearest established pattern
and state any material assumption. Ask when a missing decision changes design
direction, product-state meaning, privacy or scope. If `DESIGN.md` and the code
disagree, report the drift and apply the authority order above; do not invent a
new design rule to hide it.

When you have finished a user-visible change, check your own output against
`DESIGN.md` and the theme tokens, fix what fails, and only then present it.

The five-second state test from `DESIGN.md` applies to every surface: a user
must be able to tell a clue from a review candidate from a Map Stamp. A diff
that blurs those states fails review even if it compiles.

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
same DerivedData root and verify shutdown afterward. For a borrowed or existing
device, shutdown is the cleanup boundary. Remove a temporary device only when
this task created it and its removal is authorized; never delete another
workflow's device as routine cleanup.
CI is the canonical full checker for the native app, backend, web contracts,
and evidence rubric.

## Release Boundary

The main-branch CI builds an unsigned generic-device Release configuration with
a synthetic non-secret Google key and emits a release-readiness receipt only
after every required job passes. The binary is not uploaded as an artifact.
That receipt is evidence of code readiness, not a signed archive or deployment.
Never run `railway up`, `vercel --prod`, archive/upload to App Store Connect, or
publish a TestFlight build without explicit user approval at action time.
