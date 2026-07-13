# SAV-E memory outcome eval receipt

## Retrieval receipt

- Source boundary: eight privacy-scrubbed failure classes derived from the task's SAV-E tester-failure taxonomy; no production query, raw user record, transcript, phone number, or source URL was used.
- Fixture count: 8, one minimal synthetic reproduction per required failure class.
- Scrub/dedupe rule: opaque fixture IDs, generic venue labels, only fields needed to exercise category/evidence/ranking/status behavior, one fixture per failure class.
- Persisted fixture: `Tests/Fixtures/SaveMemoryOutcomeEvalFixtures.json`.
- Runner: `SaveSearchIntentEvalTests.testMemoryOutcomeFailureFixturesCoverRequiredScrubbedGroups`, plus focused behavior checks in `SaveLocationIntentRecommendationServiceTests` and `SaveLocalVaultServiceTests`.
- Missing evidence: this repository does not contain an approved raw tester-report corpus, so the suite preserves the real failure classes rather than copying private reports. Held-out real failures remain required before any future embedding decision.

## Baseline

The pre-change audit against `origin/main` found 5/8 classes already guarded by structured retrieval:

| Class | Baseline | Evidence |
|---|---:|---|
| wrong place/entity resolution | pass | category and specific-evidence gates |
| saved place missing after import/sync | fail | local confirmed mirror generated a different UUID and delete did not remove it |
| relevant saved place not retrieved | pass | lexical structured dish/note matching |
| unrelated memory pollution | pass | category and location gates |
| stale place/menu fact | pass for labeling boundary | existing evidence/staleness model; no general outcome label envelope |
| preference mismatch | fail | durable explicit preferences did not exist |
| hallucinated evidence/action overclaim | pass | existing claim/evidence/action guards |
| correction/removal reflected later | fail | no preference correction/removal state; local delete projection stayed active |

## Post-change

- Fixture contract: 8/8 post-change expectations pass.
- Active explicit likes/dislikes change ranking; proposed, corrected-old, and removed preferences have zero ranking influence.
- Confirmed local records keep the backend place UUID; local deletion clears the App Group projection.
- Outcome taxonomy is validated independently and does not mutate preferences.
- Focused receipt: 38 Swift tests passed, including all preference/ranking, local deletion, and eight-class fixture checks.
- Full Xcode receipt: 339 unit tests and 4 UI tests passed; standalone app/Clip/share-extension build passed on the recorded simulator.
- Backend receipt: 225 tests passed, including explicit/inferred activation policy and all nine outcome labels.

## Security and privacy receipt

- Requester scoping: every preference and outcome read/write derives `user_id` from the verified request and includes it in selection/update; outcome place and candidate UUIDs are checked against the same owner before insert.
- Phone/channel boundary: existing verified channel-to-profile resolution is unchanged. No preference promotion or outcome write is triggered from Sendblue working memory.
- Removal/correction: preferences use removed/corrected tombstones; correction creates a new active explicit row linked by `corrected_from_id`; Map Stamp deletion removes the App Group mirror before backend deletion and restores it if the backend operation fails.
- Private payloads: preference evidence and outcome references reject URLs and phone-number-shaped values; outcome records have no query/note/source-payload columns. Sendblue production logs were reduced to counts, booleans, field names, and error kinds.
- Receipt isolation: `receipt_ref` is opaque metadata and is never dereferenced by the outcome route, so it grants no commerce-data access.
- Export/backup: preference tombstones remain in authenticated backend storage for sync/audit; local Map Stamp removal is a coordinated hard delete from the App Group JSON vault. No transcript or raw outcome payload is added to device backup.
- Dependency scan: `npm audit --omit=dev` reported lockfile advisories, but `npm ls --omit=dev` confirms the named Express/body-parser/glob/mocha packages are absent from the installed production dependency tree. No unrelated dependency upgrade was made.

## Vector storage decision

`no vector database needed`

The observed failures were ownership/state-projection and explicit-control gaps, not repeated semantic-recall misses. Structured identity, category/evidence filters, status tombstones, and ranking metadata resolve the demonstrated failures without expanding the private-memory surface. Regrade only after a held-out approved real-failure set shows repeated semantic-recall misses that these controls cannot solve.
