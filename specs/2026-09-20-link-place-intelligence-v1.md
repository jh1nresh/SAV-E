# Link and place intelligence v1

User-requested scope: (1) reduce repeat analysis, (2) use explicit identity corrections, (3) associate multiple sources with one place, (5) measure aggregate saving and self-reported visits. Delivery: one reviewed PR; no merge, production migration, deployment or release. User explicitly authorized a new PR despite the existing queue on 2026-09-20.

## Implemented surface

This is a backend delivery. The native app's existing direct caption analysis and source-recovery requests gain private extraction caching. New authenticated APIs expose owner source associations and aggregate venue counts; this PR does not add a map badge or a new screen. The separate iOS account-local self-improvement task owns local correction replay, with no API dependency on this PR.

- `POST /v0/analysis/:id/extract-place-clues`: cache only validated text extraction by authenticated account and a SHA-256 key covering full input, instructions and model. Revalidate cached extraction; every analysis still verifies current Maps identity. No Places result or coordinates enter this cache. Logical TTL 24 hours, at most 100 raw entries per account; expire/prune during writes, clear on account deletion or deletion of an owned capture/place. Cache storage errors fall back to normal extraction. A deletion epoch fences in-flight writes.
- Existing `POST /v0/memory/captures/:id/search-recovery`: same extraction seam with source identity and candidate-specific provenance. Only newly inserted candidates receive the accepted semantic result fingerprint; discarded OCR passes and session-wide inference cannot replace it. Explicit source-scoped decisions may disambiguate current congruent provider matches or remove a previously corrected wrong identity; they cannot invent a replacement, coordinates or a Map Stamp.
- `GET /v0/places/:id/source-associations`: only the owner can read URLs/capture references. Several confirmed candidates may link different captures to the same saved place. Canonicalize known tracking aliases, preserve meaningful query parameters and fragments. Return distinct source URLs and whether an explicit correction supports a relationship.
- `GET /v0/place-intelligence/trending`: 30-day distinct non-guest account counts keyed by Google place ID, with separate saves and self-reported visits. Require public_link/public_guide and allow_trending_signal on each contributing place, checked live. Five accounts are required independently for each displayed count; smaller counts are null. Return at most 40 venues, ordered by supported visit count then supported save count. Source counts reflect current eligible associations, not independent creators, attributed conversions or all-city popularity. No contributor IDs, raw links, notes, ratings or account histories are returned.

## State and boundaries

A link can mention several venues. Different branches are never merged by name/proximity. Missing Google identity is unresolved for cross-user aggregation. Private/follower-only records and records without trending permission do not contribute. Linking evidence across different accounts does not share private extraction/correction data.

Place signal state is one row per saved place, recorded prospectively by database triggers. Repeated visited toggles retain the first recorded visit timestamp; currently unvisited places do not count as visited. Status edits, migration installation or identity corrections never manufacture a historical visit date. Existing rows are not backfilled. Saves and visits are overlapping populations and must not be added together as unique people. This is self-report evidence, not a verified physical visit or proof that a particular post caused it.

Decisions and source fingerprints must be attributable to the exact candidate/input. Later retries must not relabel an earlier decision's content. Changed content, conflicting decisions, deleted targets, changed provider IDs, rejected candidates and withdrawn decisions must abstain. Source-only results cannot gain coordinates through a correction.

The minimum cohort is a suppression policy, not a formal anonymity guarantee. The endpoint has no arbitrary user/time/region slicing and no user-visible raw events. There is no model training, merchant data export, new consent switch or retroactive sharing.

## Migration and containment

`backend/sql/link-place-intelligence.sql` is an additive, idempotent migration, applied after the existing schema. New internal tables enable RLS and do not grant client read/write policies. Triggers track prospective state and remove derived evidence through foreign-key cascades. No migration runs on app startup.

Before production enablement, apply only after explicit authorization, read back table/trigger definitions, and verify with an authorized account. Rollback containment is reverting backend code and disabling the task's named triggers in a separately authorized migration; preserve original places, captures and decisions. Missing new tables leave core analysis on the existing uncached path; the popularity endpoint reports migration unavailable.

## Verification and ownership

Base: `ff3aa478c0c69405f9df6c4791d95419f544ba71`. Isolated worktree: `/Users/jhinresh/projects/sav-e-link-place-intelligence`, branch `codex/link-place-intelligence`. Original dirty main and other tasks' changes are preserved. Git transport policy is retained; GitHub API objects are hash-verified locally. Commit/PR publication uses the GitHub Git Database API.

Focused tests cover source identity, cache hit/miss/corruption, fresh Maps verification, correction abstention, real SQL migration/reapply, ownership, duplicate people across different sources, revocation, deletion, legacy timestamps and bounded storage. HTTP tests use ephemeral signed fixture identities and fake provider responses; no production accounts/providers are accessed. The old server returns 404 for the new popularity request; the candidate returns the authenticated aggregate contract.

Local PostgreSQL fixture: `/tmp/save-link-intelligence/pg-data`, port 55449, database `save_link_fixture`, exclusively owned by this task. Command after compiling:

```sh
SAVE_LINK_INTELLIGENCE_TEST_DATABASE_URL='postgresql://127.0.0.1:55449/save_link_fixture' \
  node --test --test-concurrency=1 backend/dist/linkPlaceIntelligence.test.js backend/dist/linkPlaceIntelligenceApi.test.js
npm test --prefix backend
npm run audit:production --prefix backend
git diff --check
```

Required CI and independent current-head review remain the PR delivery gate. Database/HTTP fixtures require the explicit disposable URL and otherwise skip; their local results are recorded separately from CI. iOS resources: N/A, no Swift/UI files or local Xcode/simulator resources. Stop the task PostgreSQL server before closeout.
