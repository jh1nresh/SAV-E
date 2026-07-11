# SAV-E Receipt → Decision → Settlement → Reputation Loop v0

Created: 2026-07-10
Product: SAV-E / Wanderly
Repo: SAV-E
Status: PM Gate / engineering specification
Risk: medium-high — private source evidence, authenticated workflow APIs, credit settlement, and reputation state are involved.
Depends on: `specs/2026-07-10-save-inbox-first-self-learning-place-memory.md`

## 1. Executive decision

Do **not** build a broad public “reputation clearing network” yet.

Complete one narrow, auditable SAV-E vertical loop first:

```text
capture / work order
→ workflow run
→ versioned analysis result
→ analysis receipt
→ user decision
→ decision receipt
→ credit settlement
→ reputation update
```

The existing backend already contains most envelope tables and routes. This specification closes the production behavior gaps; it must not create a parallel receipt system.

## 2. Customer-paid job

When a user gives SAV-E a messy place source, they are paying for this job:

> Turn this clue into a trustworthy place memory, or explain honestly why it could not be resolved, without charging me for a technical failure.

The user does not directly pay for a blockchain, Merkle tree, or reputation score. Receipts and reputation are infrastructure that make this job trustworthy.

## 3. Current verified production baseline

Aggregate-only production inspection on 2026-07-10; no user IDs, phone numbers, URLs, or payload text were read into this artifact.

```text
workflow_receipts: 71 total
- analysis receipts: 50
- decision receipts: 21
- receipts created in the last 7 days: 50

last 7 days:
- 25 workflow runs
- 50 analysis receipts
- every run has exactly 2 analysis receipts
- 0 runs have a decision receipt
- 25 analysis pass/partial receipts
- 25 analysis failure receipts
- 0 workflow_steps
- 0 source_artifacts
- 0 evidence_items
- 25 credit_ledger records
- 0 workflow_reputation_snapshots
- 0 clearing_blocks
```

Additional verified gaps:

```text
- all 25 recent runs ended technical_failure
- all recent receipts have input/output hashes and model_provenance
- none has tool_trace_refs
- none has failure_reason
- candidate/evidence refs exist, but there is no durable stage trace
- historical user_decisions contain only confirm and needs_more_evidence
```

Interpretation:

> The schema and receipt envelope exist. The missing product is a coherent terminal-result, decision, settlement, and reputation lifecycle.

## 4. Problem statement

### 4.1 Conflicting analysis results are not versioned

A recent run can hold both a useful pass/partial analysis receipt and a later failure receipt. Both appear current because receipts lack attempt/revision/supersession semantics.

This makes it impossible to answer:

```text
What was the final accepted analysis?
Was the failure a retry, a fallback, or an overwrite?
Which receipt should reputation use?
```

### 4.2 Failure evidence is missing

`workflow_steps`, `source_artifacts`, and `evidence_items` are empty while runs fail. `failure_reason` and `tool_trace_refs` are also empty.

`technical_failure` therefore cannot be classified, reproduced, or assigned to a workflow stage.

### 4.3 Recent analysis has no user judgment

Recent runs have analysis receipts but no decision receipts. There is no current ground-truth loop for confirm/edit/reject/source-only decisions.

### 4.4 Settlement is not closed

Credits are reserved, but a technical failure should not remain pending on user review. Settlement must be deterministic and idempotent.

### 4.5 Reputation is not materialized

`workflow_reputation_snapshots` exists but is empty. Current logs cannot answer which workflow, source adapter, or model configuration is reliable for a particular source type.

### 4.6 Clearing exists before useful reputation

Offchain clearing block tables and code exist, but there are no blocks. Clearing should remain optional until receipts are current, settled, and reputation-bearing.

## 5. Goals

1. Produce exactly one **current** analysis result per run attempt.
2. Preserve retries and superseded results without pretending all are final.
3. Emit an analysis receipt on useful, partial, source-only, and failed outcomes.
4. Record a durable failure taxonomy and failed stage.
5. Turn Inbox actions into structured user decisions and decision receipts.
6. Settle credits exactly once according to explicit policy.
7. Update a privacy-safe reputation projection from settled decisions.
8. Provide authenticated aggregate inspection endpoints.
9. Preserve raw user evidence as private; receipts contain hashes and bounded refs only.

## 6. Non-goals

- Public agent marketplace.
- Public user reputation.
- Token incentives.
- Onchain settlement or payments.
- Public review network.
- Global cross-product reputation.
- Cryptographic claims about proprietary model execution beyond available provider metadata.
- New map, capture, or parser architecture.
- Model fine-tuning.

## 7. Canonical lifecycle

```text
work_order.created
→ credit.reserve
→ run.queued
→ run.running
→ attempt.started
→ workflow steps recorded
→ result recorded
→ analysis receipt emitted

technical_failure:
  → automatic refund settlement
  → run.failed
  → reputation records operational failure
  → terminal; no user decision required

review_candidate / confirmed_map_stamp / source_only_clue:
  → run.needs_review
  → user confirm/edit/reject/source_only/investigate_more
  → decision receipt emitted
  → credit settlement
  → reputation projection updated
  → run.completed or retry_requested
```

Hard invariant:

```text
analysis receipt proves what the worker produced
≠
decision receipt proves how the user/evaluator judged it
```

## 8. Result attempts and idempotency

### 8.1 Required result identity

Every worker result request must include or receive server-generated values:

```text
attempt_no
result_revision
idempotency_key
job_id
```

Recommended receipt fields:

```text
attempt_no integer not null default 1
result_revision integer not null default 1
idempotency_key text not null
supersedes_receipt_id uuid nullable
is_current boolean not null default true
failed_step text nullable
failure_code text nullable
```

### 8.2 Idempotency rules

- Repeating the same result with the same `idempotency_key` returns the existing analysis receipt.
- A conflicting result for a terminal attempt returns `409` unless it explicitly starts a retry/new attempt.
- A new attempt marks the prior attempt’s analysis receipt `is_current = false` and links it through `supersedes_receipt_id`.
- At most one analysis receipt may be current for a `(run_id, attempt_no)` pair.
- Decision receipt creation must be idempotent by `decision_id` or decision `idempotency_key`.
- Credit settlement must be idempotent by `(run_id, settlement_reason, decision_id/attempt_no)`.

## 9. Failure taxonomy

Technical failures must never be stored only as free text.

Required `failure_code` values for v0:

```text
invalid_source
unsupported_source
source_fetch_failed
source_auth_blocked
source_rate_limited
source_content_unavailable
extractor_failed
model_provider_failed
model_timeout
model_invalid_output
map_lookup_failed
candidate_persistence_failed
receipt_persistence_failed
configuration_missing
internal_error
```

Required `failed_step` values:

```text
validate_input
fetch_source
extract_source
classify_source
recover_candidate
resolve_map_identity
persist_candidate
write_receipt
settle_credit
```

Rules:

- Public/user-visible error copy remains simple.
- Internal receipt stores `failure_code`, `failed_step`, retryability, and bounded metadata.
- Never store bearer tokens, credentials, full provider responses, private messages, or raw URLs in failure metadata.

## 10. Workflow steps and evidence

For each run attempt, persist minimum stage receipts:

```text
workflow_steps:
- validate_input
- fetch_or_resolve_source
- extract_or_recover_candidate
- resolve_place_identity
- persist_result
- write_analysis_receipt
```

Each step stores:

```text
status
started_at / created_at
completed_at
error_code nullable
input_hash
output_hash
bounded metadata
```

`source_artifacts` and `evidence_items` must hold private references, not public payloads:

```text
source_artifact:
- artifact_type
- storage_ref or content_hash
- privacy = private
- safe metadata

evidence_item:
- evidence_type
- safe_summary
- confidence
- artifact_ref
```

Receipt `evidence_refs` and `tool_trace_refs` point to these records by opaque ref. They do not duplicate raw content.

## 11. User decision contract

Extend the decision taxonomy so it matches the Inbox-first product:

```text
confirm
edit
reject
source_only
wrong_place
wrong_city
wrong_branch
merge_existing
needs_more_evidence
investigate_more
```

Decision payload:

```text
decision_id
run_id
candidate_id nullable
action
reason_code nullable
edited_payload bounded/private
final_place_id nullable
idempotency_key
created_at
```

Rules:

- `confirm` may promote a candidate into a Map Stamp.
- `edit`, `wrong_place`, `wrong_city`, and `wrong_branch` preserve before/after hashes and final place reference.
- `source_only` is a useful partial outcome, not a failure.
- `reject` prevents candidate promotion.
- `investigate_more` starts a new attempt; it does not overwrite the previous analysis.
- Every accepted decision produces one decision receipt.

## 12. Settlement policy v0

| Outcome | User decision | Credit settlement | Reputation interpretation |
|---|---|---|---|
| technical failure | none required | refund | operational failure; no quality claim |
| confirmed candidate | confirm | consume | positive quality signal |
| review candidate | confirm | consume | positive bounded-quality signal |
| candidate corrected | edit/wrong_* | partial or consume by policy | useful but inaccurate; record correction class |
| source-only clue | source_only | partial | useful preservation, unresolved identity |
| false candidate | reject | refund | negative quality signal |
| insufficient evidence | needs_more_evidence | pending | no score until resolved/expired |
| explicit retry | investigate_more | keep one reservation across retry budget | prior attempt remains auditable |

Invariants:

```text
- technical_failure never waits for a user decision to refund
- settlement is written in the same DB transaction as its final receipt
- total settlement delta cannot exceed reserved credit
- a settled run cannot be settled again
- analysis quality and contract compliance remain separate fields
```

## 13. Reputation subject and projection

Do not begin with a universal agent score.

The v0 reputation subject is:

```text
workflow_id
+ workflow_version
+ source_type
+ operator/adapter id
+ model provenance bucket
```

Example subjects:

```text
save_place_recovery_v0 / instagram / source-search-worker / google:gemini-*
save_place_recovery_v0 / google_maps / deterministic-map-parser / no-model
```

### 13.1 Reputation inputs

Only settled receipts affect quality reputation:

```text
confirm
edit / wrong_*
reject
source_only
technical_failure
```

Keep separate counters:

```text
run_count
operational_success_count
technical_failure_count
confirmed_count
edited_count
rejected_count
source_only_count
refund_count
median_latency_ms
user_decision_coverage
```

### 13.2 Score policy

Do not expose one opaque score in v0. Return counters and rates first:

```text
operational_success_rate
confirmation_rate
edit_rate
rejection_rate
technical_failure_rate
decision_coverage
```

If a composite score is later required, version the policy and retain component metrics.

### 13.3 Snapshot behavior

After a decision receipt or automatic technical-failure settlement:

1. Insert the receipt and credit ledger settlement transactionally.
2. Recompute or append a `workflow_reputation_snapshots` row for the subject.
3. Store `policy_version` and source dimension.
4. Never include requester identity or raw evidence in a public reputation projection.

## 14. API requirements

Existing routes should be extended rather than replaced.

### Worker result

```text
POST /v0/workflows/place-recovery/runs/:id/result
```

Must support:

```text
idempotency_key
attempt_no
result_revision
failure_code
failed_step
retryable
workflow step refs
artifact/evidence refs
```

### User decision

```text
POST /v0/workflows/place-recovery/runs/:id/decision
```

Must support full decision taxonomy and idempotent settlement.

### Run receipt inspection

```text
GET /v0/workflows/place-recovery/runs/:id/receipts
```

Return authenticated, requester-scoped receipt history with current/superseded status. Raw private artifacts are excluded.

### Aggregate summary

```text
GET /v0/workflows/place-recovery/runs/summary
```

Add:

```text
runs_with_current_analysis_receipt
runs_with_decision_receipt
technical_failure_runs
unsettled_runs
analysis_receipt_duplicates_or_conflicts
user_decision_coverage
```

### Reputation summary

```text
GET /v0/workflows/place-recovery/reputation/summary
```

Return authenticated aggregate counters grouped by safe subject dimensions. Do not expose other users or global raw production data.

## 15. Clearing boundary

`clearing_blocks` remain an optional offchain integrity layer.

A receipt is eligible for a clearing block only if:

```text
is_current = true
receipt_hash exists
settlement is final OR receipt_type = analysis with explicit manual_review
no superseding receipt is pending
privacy validation passed
```

Do not add an onchain anchor in v0. `anchor_status = offchain` is honest and sufficient.

## 16. Customer-value eval

Use real failure classes rather than a vanity benchmark.

Seed eval suite:

1. Useful review candidate followed by confirm.
2. Candidate followed by wrong-branch edit.
3. False candidate followed by reject.
4. Source-only clue accepted as source-only.
5. Fetch failure that automatically refunds.
6. Model timeout that records failed step/retryability.
7. Duplicate delivery of the same result request.
8. Conflicting second result without retry declaration.
9. Investigate-more decision that creates attempt 2.
10. Private source whose receipt exposes only hashes/refs.

Pass criteria:

```text
- 100% of runs have exactly one current analysis receipt per attempt.
- 100% of terminal technical failures have failure_code + failed_step.
- 100% of technical failures settle as refunded exactly once.
- 100% of accepted user actions create one decision and one decision receipt.
- 0 weak/rejected candidates become confirmed Map Stamps.
- 0 raw URLs, messages, credentials, or provider payloads leak into receipt summaries.
- reputation counters reconcile exactly with current settled receipts.
- repeated idempotent requests produce no duplicate settlement or reputation delta.
```

## 17. Instrumentation

Minimum events:

```text
workflow_attempt_started
workflow_step_completed
workflow_step_failed
analysis_receipt_created
analysis_receipt_superseded
decision_created
decision_receipt_created
credit_settled
reputation_snapshot_created
retry_requested
```

Minimum operational dashboard:

```text
runs by result_type
technical failures by failed_step/failure_code
analysis receipts per run attempt
decision coverage
unsettled runs
settlement by outcome
confirmation/edit/rejection/source-only rates
reputation counters by source_type/operator/model bucket
```

## 18. Security and privacy receipt

Spec-time security scan: **N/A — no implementation diff in this artifact.** Engineering implementation must include a reachable-code-path review and test receipt.

Required controls:

- All run, decision, receipt, summary, reputation, and clearing routes remain authenticated and requester-scoped.
- Do not accept `requester_id` as authority when it conflicts with the authenticated identity.
- Server computes authoritative input/output/receipt hashes.
- Client-supplied `quality_delta`, `reputation_delta`, settlement, and score are ignored or policy-bounded server-side.
- Receipt metadata rejects secrets and limits payload size.
- Private URLs, captions, screenshots, friend messages, and provider responses do not appear in summary/reputation APIs.
- SQL mutations for decision, receipt, settlement, and reputation are transactional.
- Idempotency keys are scoped to authenticated requester + workflow + run.
- Production aggregate inspection must remain PII-free.

## 19. Implementation sequence

### P0 — Repair and observe the current workflow

1. Reproduce why recent runs emit useful analysis followed by technical failure.
2. Add `failure_code`, `failed_step`, and stage persistence.
3. Add attempt/revision/idempotency semantics.
4. Prevent conflicting terminal result overwrite.
5. Auto-refund technical failure exactly once.

Exit gate:

```text
A failed run identifies the failed stage and has one current failure receipt and one refund settlement.
```

### P1 — Close the user decision loop

1. Align Inbox actions with decision taxonomy.
2. Persist structured user decision.
3. Emit decision receipt.
4. Promote only confirmed/edited resolved places to Map Stamp.
5. Settle credit transactionally.

Exit gate:

```text
candidate → user action → decision receipt → settlement is demonstrable end to end.
```

### P2 — Materialize reputation

1. Define safe subject dimensions.
2. Populate versioned reputation snapshots from settled receipts.
3. Add authenticated reputation summary.
4. Reconcile counters against receipts in tests.

Exit gate:

```text
The product can explain which workflow configuration is reliable and why using receipt-backed counters.
```

### P3 — Optional offchain clearing

1. Admit only eligible current receipts.
2. Build offchain clearing blocks.
3. Verify block/item hashes and supersession behavior.

Exit gate:

```text
Clearing block membership is reproducible and does not imply onchain settlement.
```

## 20. Verification

Backend commands:

```bash
cd backend
npm run build
npm test
npm run check:source-recovery
```

Focused tests to add:

```text
workflow result idempotency
terminal-result conflict/retry
failure taxonomy persistence
analysis receipt uniqueness/currentness
decision taxonomy and idempotency
technical-failure automatic refund
settlement conservation
reputation counter reconciliation
requester authorization/privacy
clearing eligibility with superseded receipts
```

Production verification after approved migration/deploy:

```text
- inspect information_schema for required columns/indexes
- run aggregate-only counts for runs/receipts/decisions/settlement/snapshots
- verify no run attempt has >1 current analysis receipt
- verify no technical failure remains pending beyond processing tolerance
- verify summary endpoint matches DB aggregates for an authorized requester
```

## 21. Distribution, demand, and monetization gate

This slice is internal trust infrastructure, not a standalone launch.

```text
demand proof:
  existing production runs and user decisions already require traceable outcomes

pricing/paywall hypothesis:
  users should not lose credits for technical failures;
  successful/partial place recovery can consume full/partial credits

first distribution format:
  N/A until there is public proof of lower failure rate and successful correction loop
```

A future public proof draft may use:

```text
Problem: place agents fail silently or charge for unusable output
Build: two-receipt decision and automatic settlement loop
Proof: lower technical failure rate, zero double settlement, measurable confirmation/edit rate
Next: extend receipt-backed reputation to additional agent workflows
```

Do not publish that claim until production evidence exists.

## 22. Durable workflow classification

This work is classified as:

```text
backend workflow patch + schema migration + product decision integration
```

It is not a new skill, standalone product, or public network yet. If the lifecycle later repeats across multiple vertical agents, extract the stable receipt envelope into an AgentShack SDK/sidecar.

## 23. Definition of done

The v0 is done only when all are true:

- A run attempt has one current analysis receipt.
- Retries are explicit and preserve superseded receipts.
- Technical failures identify stage/reason and refund once.
- Candidate decisions create structured decision receipts.
- Settlement conserves reserved credit.
- Reputation counters derive from current settled receipts.
- Authenticated summaries reconcile with DB aggregates.
- Privacy tests prove raw private evidence is absent from receipt/reputation output.
- Focused backend tests, full `npm test`, build, and source-recovery check pass.
- Production migration/deploy is separately approved and verified before claiming live completion.
