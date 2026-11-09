# Social passport and place posts

User-approved feature: Home owns personal saved-place management and review;
Friends shows followed authors' explicitly shared places; Passport owns profile,
owner-only quests above an Instagram-style post grid (all / want to go / visited).
Observed failure: the passport duplicates collection management and Friends is a
placeholder; the existing social route forces a visited restaurant and rating.
No paid demand or paywall hypothesis is claimed. Distribution: existing native
app tabs after separate human-controlled release; no new monetization.

## Acceptance and privacy

- Profile header shows live post/following/follower counts, edit and settings.
- Owner tasks precede a three-column shared-post grid; larger text adapts.
- Create/edit/withdraw a post from an existing confirmed place. Caption optional
  (500 characters); rating optional and only on visited posts. Never prefill from
  private notes or imported ratings. Status is an explicit post snapshot.
- A place save, visit or follow never publishes. Feed and author passport require
  a live follow and explicit share. Private data, photos, visit time and source
  evidence are absent from social projections. Category artwork is the fallback.
- Withdrawal revokes this follower post and attribution on read, retaining both
  owner's and recipient's own places. Independently published public links/cards
  keep their existing separate lifecycle; UI explains this distinction.
- Recipient save is idempotent and preserves their existing note/status/rating.
- Unfollow/private/withdraw fixtures must remove feed/detail/author projection.
- Keep existing import, search, map, lists, preferences, Pro, tutorial and account
  controls reachable. No separate friends showcase, likes or comment system.

Scope: native social models/service, Friends, Profile, root wiring, small Home
presentation adjustment as needed; backend explicit posts/follow lists; migration
source and focused tests. No production data, dependencies or release settings.

## Design anchors

Approved Passport reference: exec-3fd5a8db-65c6-41d4-8514-d8a9e0dc0eb1.png from the
current conversation. At phone width: title in safe top band, avatar/name and
counts, compact tasks, post filters, grid, fixed existing five-tab navigation.
Use Color+Theme.swift palette (canvas/paper/forest/coral/ink/line), rounded native
typography. Clues and review candidates never look like confirmed Map Stamps.
Public Appllama Mapstr previews informed references; no authenticated MCP access.

## Verification / Xcode receipt

Project SAV-E.xcodeproj; scheme/target SAV-E; Swift 6; iOS deployment 17.
Xcode 27.0 (27A266a); generic iOS Simulator destination for build; no simulator
booted at start. Available shutdown iOS 26.5 device 04D9D2FC-9D8C-4FB4-B93E-E787FA7A3827.
Primary workflow: swift-xcode-workflow; specialist swiftui-ui-patterns.
Build: scripts/xcodebuild-clean.sh -project SAV-E.xcodeproj -scheme SAV-E
-configuration Debug -destination 'generic/platform=iOS Simulator'
-derivedDataPath /Users/jhinresh/Library/Developer/Xcode/DerivedData/SAVE-Codex
CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build.
Focused backend tests plus real local PostgreSQL privacy fixture; native logic
checks and changed-state screenshots/UI checks. Full CI before delivery ready.
Storage harness run save-social-passport-20260916; bounded cache 8 GiB; initially
13.2 GiB free. Runtime gates require sufficient free storage.

Human approval still required: production migration, merge, deployment, signing,
App Store / TestFlight release, destructive cleanup. Local migration fixture,
code, branch/commit/PR and verification are within this implementation request.

## Verification evidence before PR

- Generic simulator build and build-for-testing passed on Xcode 27.0 (no boot).
- Backend complete suite: 568 tests, 562 passed, 6 environment skips.
- Dedicated loopback PostgreSQL suite + authenticated HTTP fixture: 16/16,
  zero skips or failures. Task-owned PG stopped after the fixture.
- CI coverage selection tests passed; the frozen UI list only adds the new
  social passport/grid/composer rail, retaining every previous selector.
- Home and Map already implement the approved library/search/map ownership;
  their production presentations are retained. Profile duplication is removed.
- Task strip defaults to its first live next step; remaining tasks expand inline.
- Local disk remains 13 GiB. Native runtime/screenshot checks use CI to respect
  the Swift workflow's build-only limit at 10–15 GiB. Build is not visual proof.
- Migration shared-posts.sql remains unapplied to production. Deploy backend
  after founder applies it, before releasing the new native social client.
