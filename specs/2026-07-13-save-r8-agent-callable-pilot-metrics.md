# SAV-E R8 agent-callable pilot metrics

Created: 2026-07-13
Status: PM Gate approved for one reviewable backend PR
Risk: medium-high — authenticated cross-user aggregates over private product activity

## Decision

Add one read-only internal endpoint over the existing `recommendation_analysis_receipts` and `recommendation_outcomes` records:

```text
GET /internal/r8/pilot-metrics?days=30&limit=100
Authorization: Bearer <SAVE_INTERNAL_AGENT_TOKEN>
```

This is the smallest agent-callable record for answering whether R8 analyses are technically healthy and whether users report useful recommendations. It does not add an admin UI, a new table, a model call, learned ranking, preference mutation, or public reputation.

## Customer and operator job

The product job remains: help a user choose from places they trust. The operator job for this slice is narrower:

> Inspect a privacy-safe per-user pilot record and distinguish technical analysis quality from user-reported recommendation success.

This is an internal product-observability feature inside the R8 loop, not a new unattended loop or a public reputation product.

## Frozen semantics

- `technical_pass`, `technical_partial`, `technical_fail`, and `technical_manual_review` come only from `recommendation_analysis_receipts.evaluator_verdict`.
- A recommendation is a `product_success` when its latest linked `explicit_user` outcome contains `useful_recommendation`.
- It is a `product_failure` when its latest linked `explicit_user` outcome contains a failure label and does not contain `useful_recommendation`.
- A linked outcome with neither a useful nor failure label is `product_unresolved`. `correct_place` alone is therefore not success.
- An analysis receipt without a linked outcome is `product_pending`.
- Only `label_source=explicit_user` outcomes at or before the response `generated_at` are eligible for product metrics. The latest explicit user outcome for `(user_id, recommendation_id)` is then selected by `created_at DESC, id DESC`, so automated evals cannot supersede user feedback, later corrections cannot change an earlier snapshot, and same-timestamp writes resolve deterministically without inflating the metric.
- Outcomes link only when their `recommendation_id` equals the receipt UUID and their owner matches the receipt owner.

Failure labels are:

```text
wrong_place
irrelevant_recommendation
missing_evidence
hallucinated_fact
preference_mismatch
stale_place_or_menu
action_overclaim
```

## Privacy and authorization contract

- Server configuration is checked first. The route returns `503` when `SAVE_INTERNAL_AGENT_TOKEN` is missing or shorter than 32 characters even if the request also has a missing, malformed, or invalid bearer credential. Runtime length validation is only a fail-closed floor: deployment must generate at least 32 random bytes using the OS CSPRNG and store them in Railway's secret manager, with the generation/storage check recorded in the deploy receipt.
- Missing, malformed, or invalid bearer credentials return `401` using constant-time digest comparison.
- Raw `user_id` may exist only as a transient internal join/grouping value. The response formatter immediately converts it to a stable HMAC pseudonym; raw identity is excluded from the serialized aggregate and returned results.
- The query selects only receipt identity, transient owner identity, verdict, labels, and timestamps needed to aggregate. It must not select or return raw queries, notes, phone numbers, URLs, sources, evidence references, `private_payload`, or `public_summary`.
- The observation window is an exact rolling `days × 24 hours` interval bounded by `starts_at` and `generated_at`, inclusive, with both serialized as UTC ISO 8601 timestamps. Per-user activity is reduced to a `YYYY-MM-DD` UTC calendar date.
- Token rotation changes pseudonymous user references. Stable references across rotations are an upgrade trigger, not a v0 requirement.
- Trusted audience is limited to the founder-operated backend agent runtime and explicit operator review. The shared token must not enter iOS, browser, client logs, analytics, or third-party prompts. Successful reads write a metadata-only audit event containing the window, limit, and aggregate cohort/returned counts; it contains no token, raw user ID, or pseudonymous user row. Shared-token attribution and small-cohort re-identification remain accepted pilot risks under this restricted access; per-agent credentials are the upgrade trigger for a wider audience.

## Response contract

The response contains:

- the requested rolling UTC observation window (`starts_at`, `generated_at`) and day count;
- cohort totals computed over every qualifying user in the window;
- up to `limit` user rows ordered by most recent activity descending, then pseudonymous `user_ref` ascending for deterministic ties;
- per-user technical verdict counts, linked feedback counts, product success/failure/unresolved/pending counts, feedback coverage, repeat-use boolean, and last activity date;
- explicit metric definitions so an agent cannot silently equate evaluator pass with user success.

`days` is bounded to `1...365`, `limit` to `1...100`, with defaults of `30` and `100`.

`feedback_coverage_rate = latest linked explicit user outcomes / analysis receipts` inside the observation window; it is `0` when the denominator is zero. `repeat_usage=true` means the pseudonymous user has at least two analysis receipts inside that window; it does not mean two linked outcomes or two distinct places.

## Acceptance criteria

1. Valid internal credentials can read cohort and pseudonymous per-user aggregates.
2. Missing server configuration fails closed with `503`; bad credentials return `401`.
3. Raw user IDs are used only transiently for safe same-owner joins/grouping and are absent from serialized output; private fields are absent from both the SQL projection and output.
4. Latest-outcome deduplication and same-owner receipt linking are enforced in the query.
5. Useful, failed, unresolved, and pending fixtures produce distinct, deterministic counts.
6. Technical verdict counts remain separate from product outcome counts.
7. Query bounds, authorization, pseudonym stability, aggregation, and privacy regressions have deterministic tests.
8. The full backend suite, production dependency audit, diff checks, containment gate, and structured changed-path review pass before PR handoff.

## Harness and execution boundary

- Repo: `/Users/jhinresh/Projects/wanderly-current`.
- Branch: `codex/save-r8-agent-pilot-metrics` from `origin/main` at `ec22cb49`.
- State surface: existing recommendation analysis receipts and explicit outcome records.
- Execution surface: TypeScript module, one server route, backend documentation, and tests.
- Feedback: compiler/tests, safe SQL inspection, dependency audit, secret/private-field scan, diff review, and containment check.
- Convergence: all acceptance fixtures and full suite pass; no unresolved authorization, privacy, metric-semantics, or unnecessary-complexity finding remains.
- Dynamic harness: adversarial review because cross-user authorization and success semantics can create expensive false confidence.
- Context sensitivity: private. Tests use synthetic identifiers and labels only; no production payload or user record is read.
- Human boundary: PR review. Token configuration, merge, deployment, production smoke, dashboard UI, and pilot decisions require explicit follow-up authorization.
- Skillification: N/A. This is one product endpoint using existing records, not a repeated operator workflow.
- Xcode gate: N/A. No Swift, Xcode project, or iOS behavior is in scope.

## Verification receipt

### Implemented contract

- Added `GET /internal/r8/pilot-metrics?days=30&limit=100` before user-session resolution, guarded by a dedicated server-side bearer token.
- Added constant-time credential verification, bounded query parsing, UTC rolling-window boundaries, HMAC user pseudonyms, no-store responses, and aggregate-only output.
- Added deterministic latest-explicit-user-outcome selection and same-owner receipt linking over the existing receipt/outcome tables.
- Kept technical evaluator verdicts separate from explicit product success/failure/unresolved/pending counts.
- Added no table, dependency, model call, dashboard, public route, preference mutation, or background loop.

### Test and runtime evidence

- Frozen baseline before edits: backend `233/233` tests passed.
- Test-first receipt: the new focused suite initially failed compilation because the implementation module did not exist.
- Full backend suite after implementation and review fixes: `239/239` tests passed.
- TypeScript build: passed.
- Production-schema SQL validation: `EXPLAIN` passed through Railway against the existing PostgreSQL schema. It did not execute the aggregate, retrieve user rows, or mutate data.
- Local route smoke: missing and invalid bearer credentials returned `401`; an authenticated out-of-range query returned `400`; the response carried `Cache-Control: private, no-store`.
- Production dependency audit: `npm audit --omit=dev` reported `0 vulnerabilities`.
- Secret-pattern scan: no credential-like value found in changed paths.
- Brain containment gate: strict scan of all changed paths passed.
- `git diff --check`: passed.

### Security and privacy receipt

- Missing or shorter-than-32-character token configuration is checked before request credentials and fails closed with `503`.
- Presented credentials are reduced to fixed-length SHA-256 digests before constant-time comparison.
- The dedicated token is domain-separated when deriving 132-bit HMAC user pseudonyms; raw user IDs are transient join/grouping input and absent from serialized results.
- SQL reads only receipt ID, transient owner ID, evaluator verdict, outcome labels, and timestamps. Private payloads, summaries, preference signals, notes, URLs, phones, and evidence/source references are not selected.
- Outcomes must match both receipt UUID and owner. `DISTINCT ON` with `created_at DESC, id DESC` makes latest corrections deterministic.
- The observation window has an inclusive UTC lower and upper bound, preventing concurrent records outside the declared response window from entering metrics.
- The endpoint is read-only, does not log returned records, and marks responses private/no-store.
- Successful access audit logs contain only query bounds and aggregate row counts; they exclude credentials and user identifiers.

### Structured review receipt

- Accepted and fixed: metric definitions now state the feedback numerator/denominator and define repeat usage as two analyses in the same observation window.
- Accepted and fixed: the spec now records the stable latest-outcome tie-breaker, configuration-first `503` behavior, transient raw-ID boundary, and UTC timestamp semantics.
- Accepted and fixed from Ponytail: removed a one-use SQL parameter wrapper; native Node crypto and the existing PostgreSQL pool remain the only implementation primitives.
- CodeRabbit's first resolved pass covered all five changed paths and returned `0` findings before the final token hardening. Its post-hardening pass produced six contract/audit clarifications, all addressed above. A third pass was blocked by the CLI's 40-minute free-plan rate limit, so final validation used an independent Codex review.
- Accepted and fixed from the first independent Codex review: evaluator and deterministic outcomes could supersede explicit user feedback; product metrics now filter to `label_source=explicit_user` before latest-outcome selection.
- Final independent Codex re-review returned no actionable correctness finding and confirmed the fail-closed, aggregation, privacy, and `239/239` test boundaries.
- Final Ponytail result after the one deletion: `Lean already. Ship.`

### Residual boundary

- `SAVE_INTERNAL_AGENT_TOKEN` still needs a CSPRNG-generated value provisioned through Railway's secret manager before deployment; it was not configured in production in this task.
- Token rotation intentionally rotates pseudonymous user references in v0. A separate stable pseudonym key is the upgrade trigger if cross-rotation longitudinal analysis becomes necessary.
- The query aggregates all qualifying pilot users before applying the response limit so cohort totals remain honest. If this grows beyond pilot scale, add a database-side cohort query and pagination rather than returning more identity-level rows.
- Merge, deployment, production endpoint smoke, dashboard UI, and pilot outcome interpretation were not authorized here.
