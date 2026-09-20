# Link analysis recovery and improvement

## Scope and acceptance

Observed failure: the owner reported no venue/candidate for public Instagram
Reel `DYrOEFQRyZP`. This is bounded maintenance plus a recurring regression loop;
commercial/pricing/distribution changes are N/A. Scope: backend readiness,
source-recovery diagnostics, anonymized regression fixtures and this runbook.
No iOS UI, saved-place state, user data repair, schema auto-apply, provider settings
or spending-limit changes. All extracted places still require map evidence and
explicit user confirmation before becoming Map Stamps.

Acceptance: missing analysis tables fail the deployment health gate; restoring
the schema restores readiness; a readable caption preserves the reported venue;
unreadable/expired/empty/non-place sources remain distinct from provider outages;
no empty result asks the user to confirm a nonexistent place. Every correction
gets a failing regression before its fix. An already-passing fixture documents
coverage, not a claimed parser fix.

## Incident evidence — 2026-09-20

- Public retrieval of the reported Reel, both with and without a tracking query,
  returned a 639-character description containing `D.A ONE` and
  `臺北市信義區西村里松壽路20號二樓`. Tracking query values are not retained.
- A production diagnostic guest session could authenticate, but
  `POST /v0/analysis` returned 503 `analysis_controls_unavailable` before model or
  Places calls. This is a shared backend admission failure, independent of URL.
- A read-only `information_schema.columns` query on the managed production
  database returned zero rows for all four analysis tables: `analysis_sessions`,
  `analysis_usage_events`, `analysis_captures`, `analysis_recovery_runs`.
- The managed service's existing `/health/source-recovery` returned 200/ready
  because it checked only optional adapters. Gemini and Places keys were
  configured; analysis budget enforcement was unset, so malformed enabled
  budgets were not the observed cause. No values of credentials were recorded.
- Railway deployment `ac51b1ab-aef3-44c7-be84-4d79e19860d5` identified source
  `a6c33c94547c23f23aa8f432e89a1a719dd70025`, preceding grounded-caption changes
  in main `d677a594`. Build 127's archive receipt confirms the managed API origin.
  The user's installed build and exact failing request were not inspected.
- Other public Reel probes: `DcTZXFrjfJG` had a thin 123-character description;
  `DBSy1dOVOLM` returned no caption/image. These are retrieval observations at
  one time/location, not end-to-end accuracy claims or permanent URL failures.

Do not infer that all Reels fail for one reason. The reported Reel is readable
in this environment; other Reels can return an empty shell, require login,
expire, rate-limit requests, or contain venue evidence only inside video.
Optional server OCR/video adapters were disabled in the observed deployment.
Enabling them changes production capabilities and possible cost and is not
part of this repair.

## Failure matrix and verifier

| Failure or link shape | Correct result | Evidence |
| --- | --- | --- |
| Instagram `/p`, `/reel`, tracking query | Grounded caption candidate; never guessed coordinates | Reported Reel fixture and live retrieval |
| Instagram `/share/reel`, TikTok full/short, Xiaohongshu full/short, Threads, Douyin, Dianping | Captured caption remains usable behind a login wall | Injected resolver fixtures; not live platform success claims |
| Login wall, expired, opaque URL, missing caption | Pending source plus specific failure reason | `socialSemanticRecovery.test.ts` |
| Readable text without an explicit venue | `no_place_evidence`, request caption/screenshot/map link | Regression fixture |
| Model, media, budget, or database outage | Preserve source; failure must not become completed-empty success | Recovery, usage and HTTP integration tests |
| Conflicting/ambiguous map identity | Unresolved clue or separate alternatives; user confirms | Semantic extraction tests |
| Missing/partial analysis schema | HTTP 503 health; no deployment readiness | `analysisReadiness.test.ts`, real HTTP database regression |
| Video-only Reel | Bounded adapter evidence when explicitly enabled; otherwise request better evidence | Video adapter fixtures; live video analysis not run |

Run `npm run test:link-analysis` from `backend/` after a relevant change.
Run `npm test` for the full backend suite. The existing real PostgreSQL harness
uses `SAVE_ANALYSIS_TEST_DATABASE_URL` and the disposable database/socket
specified in `src/analysisApi.test.ts`; never point that harness at production.
CI remains the canonical broader checker. Readiness checks schema columns and
configured prerequisites, not provider key validity, quotas, live scraping
availability or semantic accuracy.

## Production repair packet — requires explicit approval

1. Recheck the managed service, database target, exact candidate commit and CI.
   Do not infer the target from a local checkout's branch or generic health.
2. Apply the existing additive `backend/sql/analysis-usage.sql` transactionally
   using `backend/scripts/apply-sql.sh analysis-usage.sql --apply` with the
   already-configured target connection supplied securely. Do not apply the
   full schema, change limits, copy accounts, or delete rows. Retain schema
   pre/post evidence and verify an idempotent second apply in the local fixture.
3. After merge/deploy approval, deploy the reviewed backend containing grounded
   caption analysis and the new readiness gate. The existing Railway health
   path must return both top-level `ready: true` and `analysis.ready: true`.
4. Replay an authorized, metered analysis of the reported public Reel through
   the deployed API, then verify the affected authenticated app path. Record
   extracted fields, map verification state, empty/failure classification and
   usage; never save or publish a Map Stamp automatically.
5. A failed gate blocks release. Additive tables can remain if application
   rollout is held; do not drop them as an automatic rollback. Deployment,
   TestFlight and device smoke are separate evidence/approval boundaries.

## Recurring improvement loop

Trigger: new user-reported link failure, changed deployment readiness, or a
previously reproduced regression. A daily task heartbeat provides the check;
unchanged known failures do not launch repeated repair work.

Durable state: this task and its atomic PR, regression tests in the repository,
and the heartbeat's last inspected commit/failure fingerprint. Keep detailed
local diagnostic reports under `.tmp/link-analysis/`; only sanitized minimal
fixtures enter Git. Do not copy whole pages, credentials, account IDs, private
captions, user locations, or tracking tokens into reports/PRs.

Maker: the task's single controller. First inspect the current PR queue and
exact code/deployment delta. Resume an existing repair, not a duplicate writer.
With new evidence, isolate the failed stage, add a failing anonymized case,
make the smallest repair and run the focused suite. A link/retrieval fixture
alone does not prove model or map accuracy.

Checker: deterministic regression suite plus independent review on the same
head, then required CI. Artifact: one atomic repair PR with evidence, failure
classification and any required deployment decision. Existing cases cannot be
weakened merely to turn the report green.

Convergence: fixture passes, preserved-state/security negatives pass, current
head review/CI pass, and the authorized delivery boundary is reached. If only
approval remains, retain the packet and stay quiet until a new user instruction
or meaningful external-state change. No automatic merge/deploy, SQL applies,
provider activation, credential/limit changes or Map Stamp creation.

Stop: unknown source provenance, missing product decision, privacy risk,
unavailable verifier/credentials, three unsuccessful repairs, or resource gate.
A provider outage is not permission to bypass rate limits, use personal login
cookies, guess a venue, or substitute an unrelated post. Notify only for a new
verified regression, completed repair, failure requiring attention, or a human
decision; unchanged healthy/known-blocked checks are no-ops.
