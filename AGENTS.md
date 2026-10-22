# Savvy Agent Contract

Savvy turns shared links, screenshots, text, and imports into place clues,
review candidates, and user-confirmed Map Stamps. The current product helps
users identify, confirm, save, and revisit places. Trip planning is not a
current product capability; legacy Plan/Trip code and tests do not establish
product scope or authorize new planning work.

External sources supply evidence. Only user confirmation establishes saved
place memory; analysis or import must not silently confirm or publish places.

## Scope And Delivery

This file adds Savvy-specific constraints to the general engineering rules; it
does not introduce a second workflow. Use `founder-engineering-workflow` for
non-trivial implementation.

- Questions and read-only audits end with findings. Documentation and local-only
  requests end with verified local changes; they do not authorize publishing.
- For PR delivery: scoped brief -> isolated branch/worktree -> smallest patch ->
  local verification -> atomic PR -> required CI and independent review.
  PR delivery ends when acceptance criteria and current-head gates pass, blocking
  findings are resolved, and the diff contains only authorized changes. Report it
  as ready for human review/merge; creating a PR alone is not completion.
- Merge, release and cleanup are separate authorized actions. Do not continue to
  them merely because implementation is complete. Reuse approval only for the
  exact still-pending operation and specified PR, build or resource. Approval
  for a completed operation does not authorize another operation or artifact.

## Required Brief

For each change, establish the observed problem or user job, scoped files and
systems, observable acceptance criteria, relevant failure fixture, verification,
and privacy/security boundaries. Keep this in working notes or the PR; reuse
known context and ask only when a missing decision affects correctness,
product meaning, privacy, payment, or authority.

For new product or commercial scope, also state the demand evidence, pricing
hypothesis if relevant, and initial distribution. Routine fixes do not need
commercial fields or a separate planning artifact. Record the authorized delivery
endpoint and any actions still needing approval. For documentation changes,
verify concrete scenarios the instructions must handle. For product-state
changes, describe the affected clue, Review Candidate and Map Stamp transitions.

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

For bounded details, follow the nearest established pattern and state material
assumptions. Report design/code drift and use the authority above within each
source's domain: palette code does not override product-state intent.
Check the finished change against `DESIGN.md` and theme tokens; fix violations
before presenting it.

The five-second state test from `DESIGN.md` applies to every surface: a user
must be able to tell a clue from a review candidate from a Map Stamp. A diff
that blurs those states fails review even if it compiles.

## Failure And Data Boundaries

- Use only task-relevant repo files and redacted fixtures. Preserve unrelated work.
- Pause affected actions for missing product boundaries, auth/payment ambiguity,
  private-data risk or unavailable credentials; continue independent authorized
  work. Report the exact blocker and what would unblock it.
- Diagnose failed checks before repairing. Retry only with new evidence or a
  narrower hypothesis; stop unchanged attempts early. If checks still fail after
  three repair attempts, report the blocker rather than continuing the loop.

## PR Queue And Closeout

- Default to at most two implementation tasks actively coding, repairing CI, or
  waiting for review; an explicit user priority or concurrency instruction takes
  precedence for the named work. A draft is not exempt while an agent is working
  on it. Park the rest with an owner, dependency, and next action in the PR;
  do not open another product task just because its predecessor is waiting.
  A bounded CI repair may proceed to unblock this queue.
- Before starting a new implementation task, inspect the open PR queue:
  `gh pr list --repo jh1nresh/SAV-E --state open --limit 100 --json number,title,isDraft,headRefName,baseRefName`.
  This is an implementation admission policy, not a gate for read-only or local
  documentation work. It must never prevent an existing PR from completing.
  No bot listener enforces this policy.
- Record predecessor PRs and the intended merge order. Update from main only
  when the PR is next for review/merge; do not repeatedly update every queued
  branch. Judge may inspect the frozen diff while CI runs, but its final verdict
  must name the same head SHA as the passing checks. A moved head invalidates it.
- The merge owner owns closeout. After explicit merge approval, verify the
  merged PR/head and main result, record the result and remaining release gate,
  then prepare the exact remote branch and local worktree cleanup candidates.
  Confirm worktree occupancy, dirty/untracked files, and unpushed commits before
  requesting deletion approval. Never delete solely because a PR is closed;
  squash merges need the PR merge record, not just ancestry. Merge does not
  authorize deployment or branch deletion.

## CI Coverage

- iOS-relevant PRs retain the generic build and all `SAVETests`. Exact-file UI
  routing and maintained test profiles live in `scripts/select-ios-tests.py`.
  Preserve production visual parity at 0.90, navigation smoke, and existing
  legacy Plan/Trip coverage; test names do not define current product features.
- Shared navigation/theme/data, test harness, project, workflow, and unknown
  changes run full integration coverage. Multiple known surfaces run the union;
  renames consider both paths. An unavailable or empty diff runs full coverage.
  Unit-test-only changes build and run units without UI. Existing non-iOS
  exclusions remain in effect.
- Automatic PR/push iOS gates are `ios-build` and `ios-fast`. The full UI +
  snapshot + 0.90 parity job named `ios` runs only on manual
  `workflow_dispatch` of the iOS workflow; it is not an automatic required
  check. PR success on those gates is not full integration or release
  evidence. Review the `save-test-selection-<sha>` artifact (from a manual
  `ios` run) and Actions step summary for the selected profile.
- Coverage-map changes must pass
  `python3 -B -m unittest discover -s Tests/ci -p 'test_*.py' -v`.
  The frozen baseline prevents accidentally dropping existing full-suite tests;
  each new allowlisted source file needs a reviewed UI coverage mapping.

## Verification

Choose checks for the changed behavior; documentation-only edits need a scoped
diff, reference and instruction-consistency review, not a simulator build.
CI remains the canonical full checker for the native app, backend, web contracts
and evidence rubric; local checks do not waive required CI coverage.

For ordinary iOS edits, compile without booting a simulator. Check disk space and
export `SAVE_DERIVED_DATA_PATH` as a task-specific absolute path first, following
`docs/verification.md`. This also configures the social regression helper.
Reuse an existing
cache only with exclusive ownership enforced by a lock or one serialized build
owner; an idle process snapshot is insufficient.

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${SAVE_DERIVED_DATA_PATH:?Export a task-owned DerivedData path}" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build
```

Below 10 GiB free, block new Xcode/runtime work until authorized cleanup or
explicit acceptance of that task's storage risk. Boot one headless simulator
only for focused XCTest or UI evidence, with exclusive device ownership.
Reuse the task-owned DerivedData root and verify Shutdown
afterward. For a borrowed device, shutdown is the cleanup boundary. Remove a
temporary device only when this task created it and removal is authorized.

## Approval And Release Boundaries

Merge requires explicit approval for the target, independent review PASS on the
current head, required CI green, and no blocking findings. Production schema or
secrets changes, deployment, signing, App Store Connect, TestFlight, external
messages, and destructive cleanup require their own explicit authorization.

A manual iOS workflow dispatch builds an unsigned generic-device Release
configuration with a synthetic non-secret Google key and emits a
release-readiness receipt only after the full `ios` suite passes. Automatic
required checks are `ios-build` and `ios-fast`. The binary is not uploaded as
an artifact.
That receipt is evidence of code readiness, not a signed archive or deployment.
Before `railway up`, `vercel --prod`, archive/upload or TestFlight publication,
verify that explicit approval covers the exact pending operation, artifact and
target. Do not reuse a completed operation's approval for a later release.
