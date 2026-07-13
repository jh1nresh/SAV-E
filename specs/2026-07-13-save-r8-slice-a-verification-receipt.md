# SAV-E R8 Slice A verification receipt

## PM decision

- Source spec: `/Users/jhinresh/brain/wiki/projects/wanderly/save-r8-experience-recommendation-loop-spec.md`.
- Product boundary: R8 remains a private recommendation capability inside SAV-E. This slice does not add a public review network, standalone R8 surface, commerce, SLL-R, UI, outcome learning, or deployment.
- Customer-paid job: help a user choose from places they already trust without treating a visit as proof that they liked the place.
- Work type: the experience-contract feature inside the larger R8 product loop.
- Slice: A only. Slice B owns UI and the canonical context-aware recommendation policy. Slice C owns outcome UI, pilot evidence, and the privacy-safe distribution draft.
- Pilot city and situation: N/A for Slice A because this branch has no city, UI, pilot, or learned ranking configuration. No city is hardcoded. Selection remains required before Slice C.

## Harness

- Repo: `/Users/jhinresh/Projects/wanderly-current`.
- Branch: `codex/save-r8-experience-contract` from `origin/main` at `6d107df7`.
- State surface: `place_claims`, the verified-claims route, deterministic claim ranking, claim tests, and the declarative backend schema.
- Execution surface: TypeScript build/tests, Xcode build/tests, dependency audit, diff checks, and manual changed-path review.
- Feedback: compiler/test output, schema and route inspection, dependency audit, diff review, and privacy regressions.
- Convergence: contract tests and full suites pass; owner, privacy, idempotency, and delete invariants have deterministic coverage; no accepted review finding remains.
- Human boundary: PR review. Merge, schema application, deploy, pilot, and public proof require separate explicit action.
- Dynamic harness: loop-to-completion, local serial implementation; no subagents or unattended optimization loop.
- Context sensitivity: private. Provider-visible context was limited to the product spec and privacy-scrubbed synthetic fixtures. No production data or secrets were used.

## Xcode context receipt

| Field | Receipt |
|---|---|
| Product/repo | SAV-E in `/Users/jhinresh/Projects/wanderly-current` |
| Platform | Mixed iOS app plus Node/TypeScript backend |
| Project | `SAV-E.xcodeproj` |
| Scheme/target | `SAV-E` / `SAVE`; dependency build includes `SAVEClip` and `SAVEShareExtension` |
| Simulator | iPhone Air, iOS 26.5, `53A8DA29-D4F6-43AF-A81E-47929D1DF97D` |
| Deployment/Swift | iOS 17.0 / Swift 6.0 |
| XcodeBuildMCP | Unavailable; repository `scripts/xcodebuild-clean.sh` fallback used |
| Touched surface | Backend only; no Swift or Xcode project edit |
| Skill route | `swift-xcode-workflow`; no Swift specialist needed for a backend-only slice |
| Build command | `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E -configuration Debug -destination 'platform=iOS Simulator,id=53A8DA29-D4F6-43AF-A81E-47929D1DF97D' CODE_SIGNING_ALLOWED=NO build` |
| Test command | Same wrapper and destination with `test` |
| Skipped verification | None |

## Existing-model audit

`place_claims` already supplies the required owner, place, structured context and ratings, observed time, staleness, evidence references, and cascade-delete semantics. The recommendation query reads live rows, and `claim_usage_receipts` cascades on claim deletion. A new experience table would duplicate ownership and serving state, so it was rejected.

The minimum schema extension is one opaque `idempotency_key` column, one partial unique index for `experience_review`, and a check constraint for the subtype invariants. The schema file is declarative input only; no local or production database migration was executed in this branch.

## Implemented contract

- `POST /v0/places/:placeId/verified-claims` accepts `claim_type=experience_review` only for an authenticated, owner-scoped place.
- Required fields are a valid `observed_at`, a bounded occasion, and `ratings.would_return` of `yes`, `no`, or `unsure`.
- Experience claims are forced to `visited_self_reported`, self-authored, and private; public visibility and client-supplied public identity fail closed.
- Strengths and misses use the frozen bounded vocabulary. Multiple visits remain distinct because the observed time participates in the create fingerprint.
- Exact create retries return the existing row through a database uniqueness boundary instead of creating a second visit.
- `PATCH /v0/places/:placeId/verified-claims/:claimId` edits only the private experience fields.
- `DELETE /v0/places/:placeId/verified-claims/:claimId` hard-deletes the owner-scoped experience. Cascades remove claim usage projections, and live recommendation reads lose the row immediately.
- Raw private note text is owner-visible claim data only. It is excluded from the derived agent summary, ranking tokens, warning detection, and analysis detail extraction.
- Until Slice B supplies context-aware negative demotion fixtures, only `would_return=yes` experience claims can enter the legacy claim ranker. `no` and `unsure` are not treated as likes.

## Verification

- Frozen baseline before edits: backend `225/225` tests passed.
- Focused experience and claim tests: `23/23` passed.
- Full backend suite after edits: `233/233` tests passed.
- Production dependency audit: `npm audit --omit=dev` reported `0 vulnerabilities`.
- Xcode simulator build: passed for app, App Clip, and share extension.
- Full Xcode tests: `340/340` unit tests and `5/5` UI tests passed; result bundle at `/Users/jhinresh/Library/Developer/Xcode/DerivedData/SAV-E-ahydqktpduridpbzrzurshjbxqni/Logs/Test/Test-SAV-E-2026.07.13_16-22-51-+0800.xcresult`.
- `git diff --check`: passed.

## Security and privacy receipt

- Identity is resolved before the route, and place ownership is checked before every operation.
- PATCH and DELETE share one predicate containing claim ID, place ID, authenticated user ID, claim type, self authorship, and private visibility; foreign object IDs return not found.
- The uniqueness index is scoped by authenticated user and place. The idempotency fingerprint is server-derived and is not returned in public envelopes.
- Public visibility is rejected in both TypeScript validation and the database subtype constraint.
- No new log statement was added. Private note text is absent from agent-facing analysis and ranking inputs.
- Delete uses the existing foreign-key cascade and live serving query; there is no second experience projection to reconcile.
- Dependency scan found no production advisory. No dependency changed.
- Brain containment gate: `scripts/brain containment check --strict` passed before PR handoff.
- Schema syntax and behavior were reviewed against the existing PostgreSQL patterns, but the declarative schema was not applied to production.

## Structured review receipt

- Accepted and fixed: raw private note text originally flowed through the legacy ranker, warning scan, and analysis detail extraction; experience claims now expose only the structured note-free summary to those consumers.
- Accepted and fixed: PostgreSQL check constraints treat a null expression as passing; required JSON keys now use `coalesce` so missing occasion or return intent fails closed.
- Accepted and fixed: an invariant-only PATCH could otherwise be reported as an edit; the normalizer now requires at least one mutable field.
- Rejected for this slice: full negative/context-aware ranking. That policy and its fixtures belong to Slice B; Slice A only prevents `no` and `unsure` experiences from becoming positive legacy signals.
- Final changed-path review: no unresolved correctness, authorization, privacy, or unnecessary-complexity finding remains.

## Complexity review

- Native Node crypto and existing query builders are reused; no dependency, table, repository abstraction, model service, or workflow was added.
- The mutation-scope helper exists only to keep the authorization predicate identical and testable across read-before-patch, PATCH, and DELETE.
- Vector storage, embeddings, learned weights, public review identity, and speculative fallback layers are deliberately absent.

## Residual boundary

- Slice B must add the full context-aware ranking fixtures before a negative experience can demote a previously positive or public signal. Slice A only guarantees that non-positive experience rows are not promoted as likes.
- Production schema application and API smoke against a migrated environment remain deployment work and were not authorized here.
- Pilot city, pilot users, 30-50 experiences, 15 outcomes, repeat-use evidence, and the distribution draft remain Slice C evidence targets; this receipt makes no pilot claim.
