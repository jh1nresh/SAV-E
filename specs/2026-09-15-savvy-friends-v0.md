# Friends v0 execution

Source: `/Users/jhinresh/brain/raw/inbox/2026-09-15-savvy-friends-v0.md`.

Job: a known friend's explicitly shared restaurant rating helps a recipient
choose a restaurant to try. Feature/social loop; demand is a founder/friend
conversation, not retention or willingness to pay. Pricing unchanged; first
distribution is a manually invited friend group.

Base: `6c38ee004ca58d2a7d863a4a941e67b3c959ed28`, merged PR #240;
GitHub main verified on 2026-09-15. Open implementation PR queue was empty.
Canonical checkout has unrelated changes; implementation belongs only to
`/Users/jhinresh/projects/sav-e-friends-v0`, `codex/savvy-friends-v0`.

Acceptance: preserve Home/Map/capture/Passport and child routes; add Friends;
explicit eaten affirmation and owner-entered 1–5 stars; paginated recent feed;
known-friend follow; idempotent want-to-go save without copied ratings; owner
edit/withdraw; private details and revoked attribution inaccessible after refresh.
Use the source brief's eight requirements and A/B/C failure fixtures in full.

Scope: native Friends surface, API adapter, navigation, backend rating/share
projection and save transaction, local draft SQL, focused privacy tests. No
contacts, uploads, notifications, agents, public directory, or production access.
Existing `friends` visibility means anyone following the author, not reciprocal
friendship. UI must disclose that audience. Private notes, private ratings,
source material and visit timestamps are never social projection fields.

Verification: backend `npm run build`, `npm test`; local PostgreSQL privacy
fixtures; generic iOS build; multi-account native flow, empty/populated screenshots,
and shutdown at runtime gate. No `audit:production` or `npm run validate`.
Merge, production migration/deployment, signing and distribution need separate
approval. The controller owns integration and the remaining verification gates.

Xcode context: `SAV-E.xcodeproj`, scheme/target `SAV-E`, iOS 17 minimum;
`SAVETests` and `SAVEUITests`. Generic destination `generic/platform=iOS Simulator`;
canonical DerivedData `/Users/jhinresh/Library/Developer/Xcode/DerivedData/SAVE-Codex`.
Route: swift-xcode-workflow + swiftui-ui-patterns. Direct repository
`scripts/xcodebuild-clean.sh`; XcodeBuildMCP unavailable, physical devices ignored.
Runtime target: existing headless iPhone 16 Pro / iOS 26.5,
`C6EE29A5-D23E-47C7-BAC5-F240CF5F6EC0`. Resource receipt:
`.resource-state/savvy-friends-runtime.json`. The prior storage blocker was
removed by separately authorized DerivedData/DeviceSupport cleanup; this run
began with 25.6 GiB free. No simulator deletion is authorized.

## Verification and delivery

- Generic `build-for-testing` passes for the real app and both test bundles.
- Backend `npm test`: 521 tests, 519 passed, 0 failed, 2 existing analysis
  integration skips. Friends tests actually use local PostgreSQL on loopback
  port 55439 in the dedicated `savvy_friends_test` database.
- A/B/C fixtures cover private/shared stars, owner spoofing, guessed IDs,
  pagination, concurrent save dedupe, edited ratings, withdrawal, visibility
  revocation, unfollow, and recipient-owned note/rating/visit preservation.
- Real HTTP tests sign local ES256 JWTs and run the production server with a
  test verification key. Private-to-friends sharing never introduces public
  permissions. Rated venues cannot enter the legacy social-save path, whose
  persisted recommender would bypass revocation. Existing unrated legacy
  shares remain visible. Both withdrawal and a private edit revoke access.
- Mutating away either the follower check or the legacy-exclusion check makes
  the corresponding privacy assertion fail. Original code restored afterward.
- Independent source review identified the legacy leak and permanent
  attribution path; both are fixed and the follow-up found no new reachable
  privacy blocker. Final head-bound verdict is recorded in the delivery receipt.
- Native test `SAVEScreenshotRailTests/testLocalFriendsAuthenticatedFlow`
  exercises production ContentView/Friends/MapViewModel with injected local
  HTTP service and isolated vault. The entry is Debug + simulator only,
  requires an explicit flag and fixed loopback URL, and visibly says LOCAL TEST.
  Its local JWTs are generated at runtime; no production tokens or keys are used.
  Without the fixture, this optional test skips; CI is not local-account proof.
- Reproduce backend/native fixture with
  `SAVE_FRIENDS_TEST_DATABASE_URL=postgresql://friends_test@127.0.0.1:55439/savvy_friends_test node backend/scripts/friends-local-fixture.mjs --native`.
  Backend listens only on 127.0.0.1:55440; the test-only credential handoff is
  127.0.0.1:55441. Stop the fixture and PostgreSQL after verification.
- SQL draft `backend/sql/friend-ratings.sql` must be applied before deploying
  this backend. It has only been applied to the local disposable database.
  Production migration, merge, deployment, signing and distribution remain
  separate human-controlled actions.
- Repository Git transport policies stay unchanged. Authorized branch/PR
  delivery can use the existing GitHub Git Database API route with blob,
  tree, commit and remote-ref hash verification.

- Native `SAVETests`: 858 executed, 857 passed, 1 existing opt-in live-provider
  evaluation skipped, zero failures. Local Friends UI acceptance: 1 executed,
  zero failures, 84.884 seconds. B explicitly rated/shared; A saw and saved it;
  Home and Map saved-place search showed the recipient-owned Map Stamp; C was
  denied; B withdrew; A's rating feed/attribution cleared while its own save remained.
- Controller reviewed the final empty/populated five-tab screenshots against
  DESIGN.md, plus rating editor, Home, Map saved-place search and withdrawal.
  Screenshots and xcresult bundles are under this worktree's `.verification/`.
- The first fixture run exposed repeated auth initialization; guarded the
  Debug fixture. The next run exposed UI automation tapping toggle labels;
  the test now taps actual switch controls and verifies their on-state before
  submission, then waits for editor dismissal. Production consent gates stayed
  enforced. The final complete run includes the stronger Map search assertion.
- Simulator shutdown independently verified; local fixture server and PostgreSQL
  stopped. Resource lifecycle finished with zero violations.

Owner: controller on `codex/savvy-friends-v0`. PR carries current CI/review state.
Merge, production migration/deployment and distribution remain unperformed.

PR #241 saved-state follow-up: refreshing or paging Friends now reloads saved
rating IDs from the current access-checked `/v0/friend-ratings/saved` response.
The native regression leaves Friends after saving, returns, and requires the
restored Saved label and disabled action before continuing Map/withdrawal checks.
Verification: `.verification/friends-saved-state.log`; 858 native units
(1 existing opt-in skip), plus the complete real HTTP/native flow, all passing.
Resource receipt: `.resource-state/savvy-friends-saved-state.json`.
