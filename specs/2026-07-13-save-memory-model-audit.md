# SAV-E explicit memory and outcome PM gate

## Product decision frame

- Customer-paid job: recover places the user cares about and make grounded decisions from their evidence and stated preferences.
- Demand proof: the task is grounded in observed wrong/missing retrieval, preference mismatch, and correction/removal trust failures; no generic memory-framework claim is used as demand proof.
- Pricing hypothesis: understandable private memory strengthens the existing premium value; there is no separate vector-memory upsell.
- First distribution format: a synthetic private-first demo showing `why -> correct/remove -> next recommendation changes`.
- Durable implementation class: product code plus deterministic eval fixtures. This is not a reusable skill or a new workflow platform.
- Security gate: required because the slice adds private preference/outcome records and changes deletion semantics.

## Xcode context receipt

| Field | Receipt |
|---|---|
| Repo | `/Users/jhinresh/projects/wanderly-memory-outcome-eval` at `origin/main` `42770fd2` |
| Project | `SAV-E.xcodeproj` |
| Scheme / targets | `SAV-E` / `SAVE`; dependency graph includes `SAVEClip` and `SAVEShareExtension`; iMessage target is unaffected |
| Simulator | iPhone Air, iOS 26.5, `53A8DA29-D4F6-43AF-A81E-47929D1DF97D` |
| Deployment / Swift | iOS 17.0 / Swift 6.0 |
| Tool route | shell `xcodebuild` fallback; `swift-xcode-workflow`, SwiftUI UI patterns, Swift testing |
| Focused verification | `scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,id=53A8DA29-D4F6-43AF-A81E-47929D1DF97D' CODE_SIGNING_ALLOWED=NO -only-testing:SAVETests/SaveLocationIntentRecommendationServiceTests test` |
| Full verification | same command without `-only-testing`, plus a build invocation |

## Current model map

| Existing model/store | Current owner | Lifetime | Source/evidence | User editable? | Proposed tier | Gap |
|---|---|---|---|---:|---|---|
| `AIDrawerViewModel` conversation turns | iOS invocation | Five turns / current drawer session | User query and bounded model response | No | Working | Correct tier; must not promote silently |
| Sendblue `ConversationState` | Phone/channel memory key | Ten-minute TTL | Current query, shown/recommended IDs, review/order context | Indirectly | Working | Correct tier; profile binding remains channel-verified |
| `captures` + `place_candidates` | Authenticated profile | Cross-session until archived/deleted | Raw clue plus candidate evidence/confidence | Candidate status is editable | Place/experience | Already the Clue/Review envelope; do not duplicate |
| `places` + `SaveMemoryRecord.confirmedPlace` | Authenticated profile plus local App Group mirror | Cross-session | Source URL/note, structured evidence, rating/status | Yes | Place/experience | Delete does not remove local mirror and can resurrect stale state |
| `place_claims` + claim receipts | Authenticated profile | Cross-session | Proof level, evidence refs, confidence, staleness | Via claim APIs | Place/experience | Already distinguishes inference/source/receipt proof |
| Sendblue saved places / visits / reviews | Canonical phone memory key | Cross-session | Save action, verified receipt, receipt-gated review | Through bot flows | Place/experience | Keep separate; no automatic cross-profile merge |
| `SaveTasteProfile` | iOS recommendation service | Recomputed per request | Saved/tried places, ratings, tags, price | No | Preference input | Implicit signals are not inspectable; one save can contribute silently |
| Sendblue `buildTasteProfile` | Bot request | Recomputed per request | Saved categories and visited merchants | No | Preference input | Must remain an implicit request signal, not durable active preference |
| `recommendation_analysis_receipts` | Authenticated profile | Cross-session receipt | Query/result hashes, safe signal descriptors | No | Outcome evidence | No user/evaluator outcome taxonomy |
| `claim_usage_receipts` | Authenticated/guest receipt subject | Cross-session receipt | Accepted/rejected/unknown claim use | No | Outcome evidence | Too claim-specific to become the general outcome envelope |

## Frozen implementation boundary

1. Preserve the current bounded working-memory implementations and document their non-promotion boundary in code.
2. Preserve captures, candidates, places, claims, receipts, and Sendblue stores as the place/experience layer; add a local-vault removal operation so backend deletion cannot leave an active stale projection.
3. Add one compact owner-scoped `memory_preferences` envelope because no existing record supports status, polarity, context, evidence count, confidence, and user correction/removal.
4. Add one owner-scoped `recommendation_outcomes` envelope because existing receipts describe execution but do not store the required multi-label outcome taxonomy. Outcome writes never mutate preferences.
5. Feed only active explicit preferences into iOS ranking. Proposed, corrected-old, and removed records are excluded. Existing inferred `SaveTasteProfile` remains request-local and does not become durable preference memory.
6. Add a scrubbed eight-class fixture suite and record baseline/post-change receipts. Do not add embeddings or vector storage unless the eval proves a semantic-recall gap.

## Storage and removal decision

- Preference removal is a tombstone (`status = removed`) so sync cannot resurrect it and audit timestamps survive; raw private source payloads are not stored.
- Correcting a preference marks the old record `corrected` and creates/activates the corrected value through the same owner-scoped API.
- Map Stamp deletion is hard-delete in the backend and immediate removal from the local App Group mirror.
- Outcome records retain opaque IDs/hashes and labels, not queries, notes, phone numbers, source payloads, or unnecessary URLs.
- No production migration or data query is part of this branch; `backend/sql/schema.sql` is the declarative migration input only.

## Acceptance and verification

- Active/proposed preferences are inspectable; proposed records can be confirmed/rejected; active records can be corrected/removed.
- The next recommendation receives only active preferences; a removed record has zero ranking influence.
- Every preference/outcome backend operation is scoped by the authenticated `user_id`.
- Outcome labels are validated and stored independently from preferences.
- Eight scrubbed failure groups execute before and after the change, with an explicit vector-store decision.
- Focused Swift/backend tests, full backend tests, app tests/build, delete/import/sync regressions, UI smoke, dependency scan, `git diff --check`, and containment review complete before ship.
