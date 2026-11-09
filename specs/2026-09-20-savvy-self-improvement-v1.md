# Account-local correction learning v1

Implementation requested 2026-09-20 after the research-only phase. Delivery is a scoped PR; merge, release and backend schema changes remain separate. Base: `ff3aa478c0c69405f9df6c4791d95419f544ba71`. The explicit request to open this PR supersedes the earlier queue wait. Existing #255/#257/#261 remain untouched. The concurrent link-place-intelligence PR #262 owns backend evidence/cache/statistics; this patch owns iOS replay, with no new API dependency. Review after the existing import PR #261 to resolve any import-path conflict once, without repeatedly rebasing the queue.

## User-visible result

After the user confirms the correct branch, a later matching review candidate can suggest that saved identity with the explanation “Suggested from your previous correction of this source. Confirm the place.” It stays a review candidate. Only another explicit confirmation saves a Map Stamp.

Current Savvy is a bounded source-analysis/recovery workflow. Legacy Plan/Trip implementation is not evidence of current product scope. This feature adds deterministic reuse of explicit user corrections; it does not train model weights or autonomously rewrite prompts.

## Loop and trust boundary

- Trigger: candidate refresh after an import/reanalysis or opening the existing review queue.
- Evidence: successful same-account confirmation/identity-edit/merge event, final saved-place ID and snapshot.
- Scope: versioned SHA-256 of canonical source URL, exact source text and original candidate name/address. Tracking parameters may differ; changed content, different source or different venue slot cannot reuse the association.
- State: the existing bounded correction-event file; new optional scope/commit/revocation fields. Legacy events remain readable but cannot activate learning. Duplicate receipt updates replace the same event ID.
- Checker: the latest decision must be unambiguous, committed and not revoked; fresh server-owned places must still contain the exact unchanged target. Owner filtering precedes the result limit. A newer uncommitted/negative decision suppresses old positives.
- Action: a transient review projection using the current saved identity, without provider calls or writes to saved-place truth. Old provider-location metadata is removed from the projected evidence.
- Invalidation: refresh rechecks deletion/identity changes; selected detail state reconciles with refreshed candidates. Account transitions discard projected private state immediately. Local deletion reverts visible suggestions immediately. Confirmation rechecks target liveness and session before using a projected identity.
- Rollback: `MapViewModel(correctionLearningEnabled: false)` returns to the existing review path without deleting events or user decisions. This is an implementation switch, not a new user setting or remote rollout system.
- Stop/fallback: corrupt/missing store, no source text, missing account, old metadata, conflicting decisions, changed target or failed liveness fetch leaves normal review intact. Source-only and coordinate-less clues stay unchanged.

No cross-account learning, historical backfill, private transcript export, automatic saving, new provider/model calls, scheduler, production data migration or global instruction adoption is included. Raw free-text reasons are never executable instructions.

## Deliberate first-version limits

The structured scope is emitted on the native `createPlaceCandidate` path using existing opaque evidence JSON. Backend-generated recovery candidates without this metadata abstain. Already-terminal duplicate imports retain the existing “already reviewed” behavior. Different-source transfer, unavailable-caption cases and model-quality improvement are not claimed. Recommendations and ranking weights stay unchanged.

Corrections are local to the device/account evidence file; syncing rules across devices is separate work. Eligibility is re-derived at refresh, not a persistent trained model. A pending record is written before remote decision submission and becomes eligible only after success in the same session. If the best-effort local commit receipt fails, user success remains committed remotely and learning stays disabled for that record.

## Verification

Independent scenarios and baseline source hashes were frozen before edits. The identical baseline-compatible XCTest class exercises the actual `SupabaseService` decoder and `MapViewModel.refreshReviewCandidates`; no imitation baseline scorer or model accuracy claim. Public regression coverage includes transfer to a new capture, replacement, retention, account isolation, pending/legacy/conflicting/negative decisions, deletion/changed target, corrupt storage, source-only, meaningful source-content scoping and zero provider writes.

Developer tests additionally cover rollback, immediate logout/selection invalidation, account switch during liveness fetch, failed remote decisions, account filtering before truncation and duplicate event receipts. Focused native tests use one task-owned simulator; CI retains full iOS integration because shared data and MapViewModel changed. The `save-test-selection-<sha>` artifact is the coverage receipt. Final executed results and independent current-head review belong in the PR, not invented scores in this design.

Method references: [CS329A verifier/feedback lecture](https://youtu.be/6YnLB0XbTnI?t=1261) and [AI Agent Book chapter 9](https://github.com/bojieli/ai-agent-book/blob/1be5fd4f235b4af382a4403617f2d1657b719d94/book/chapter9.md). Apply feedback → minimal candidate → independent replay → reversible adoption. External sources are method evidence, never application authority.
