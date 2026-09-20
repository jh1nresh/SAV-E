# Savvy Agent Contract

Savvy turns shared links, screenshots, text, and imports into place clues,
review candidates, and user-confirmed Map Stamps. The current product helps
users identify, confirm, save, and revisit places. Trip planning is not a
current product capability; legacy Plan/Trip code and tests do not establish
product scope or authorize new planning work.

External sources supply evidence. Only user confirmation establishes saved
place memory; analysis or import must not silently confirm or publish places.

## Required Brief

For each change, establish the observed problem or user job, scoped files and
systems, observable acceptance criteria, relevant failure fixture, verification,
and privacy/security boundaries. Keep this in working notes or the PR; reuse
known context and ask only when a missing decision affects correctness,
product meaning, privacy, payment, or authority.

For new product or commercial scope, also state the demand evidence, pricing
hypothesis if relevant, and initial distribution. Routine fixes do not need
commercial fields or a separate planning artifact.

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

## Delivery

Use `founder-engineering-workflow`: scoped problem → isolated branch/worktree →
smallest patch → focused verification → atomic PR → CI and independent review.
Preserve unrelated work and use task-relevant files and redacted fixtures.
Done means acceptance passes, current-head checks pass, review has no blocking
findings, and the diff contains only the authorized scope. PR creation alone
is not completion.

Stop dependent work for unresolved product/auth/payment/privacy boundaries,
unavailable credentials, or failing checks after three repair attempts. Keep
independent work moving and report the concrete blocker.

## PR Queue And Closeout

- Default to at most two implementation tasks actively coding, repairing CI, or
  waiting for review; an explicit user priority or concurrency instruction takes
  precedence for the named work. A draft is not exempt while an agent is working
  on it. Park the rest with an owner, dependency, and next action in the PR;
  do not open another
  product task just because its predecessor is waiting. A bounded CI repair may
  proceed to unblock this queue.
- Before starting another task, inspect the open PR queue:
  `gh pr list --repo jh1nresh/SAV-E --state open --limit 100 --json number,title,isDraft,headRefName,baseRefName`.
  This is an admission policy, not a required CI check: a queue limit must never
  prevent an existing PR from completing. No bot listener enforces this policy.
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
- Main pushes and manual `CI` workflow dispatches run full integration coverage.
  PR success on a focused route is not full integration or release evidence.
  Review the `save-test-selection-<sha>` artifact and Actions step summary for
  the selected profile. The required job names and main release gate stay fixed.
- Coverage-map changes must pass
  `python3 -B -m unittest discover -s Tests/ci -p 'test_*.py' -v`.
  The frozen baseline prevents accidentally dropping existing full-suite tests;
  each new allowlisted source file needs a reviewed UI coverage mapping.

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

Below 10 GiB free, block new Xcode/runtime work until authorized cleanup or
explicit acceptance of that task's storage risk. Boot one headless simulator
only for focused XCTest or UI evidence. Reuse the
same DerivedData root and verify shutdown afterward. For a borrowed or existing
device, shutdown is the cleanup boundary. Remove a temporary device only when
this task created it and its removal is authorized; never delete another
workflow's device as routine cleanup.
CI is the canonical full checker for the native app, backend, web contracts,
and evidence rubric.

## Approval And Release Boundaries

Merge requires explicit approval for the target, independent review PASS on the
current head, required CI green, and no blocking findings. Production schema or
secrets changes, deployment, signing, App Store Connect, TestFlight, external
messages, and destructive cleanup require their own explicit authorization.

The main-branch CI builds an unsigned generic-device Release configuration with
a synthetic non-secret Google key and emits a release-readiness receipt only
after every required job passes. The binary is not uploaded as an artifact.
That receipt is evidence of code readiness, not a signed archive or deployment.
Never run `railway up`, `vercel --prod`, archive/upload to App Store Connect, or
publish a TestFlight build without explicit user approval at action time.
