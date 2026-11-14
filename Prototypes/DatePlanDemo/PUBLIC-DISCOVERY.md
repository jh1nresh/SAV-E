# Public social-post discovery — local implementation contract

## Job and scope

Opening Map should reveal geographically associated public Instagram, Threads and Xiaohongshu posts without a personal import. Keep Saved / Map / Passport and search; Map has Explore (default), Mine and Friends. Public post browsing never creates a saved place, visit, follow or endorsement. Explicit Save uses canonical venue confirmation; Guide continues through an explicitly selected shared list.

The existing follower feed, private captures/notes, capability links and anonymous place aggregates do not satisfy this job and are not fallback sources. External access/coverage is still unknown. Start with the existing Taipei/Shanghai MVP geography and preserve arbitrary map navigation. The Guangzhou reference does not add another supported district or require authored3D.

This implementation establishes a dedicated read-only public index and native UI. Use a bounded operator-supplied index artifact rather than migrating or reading private account tables. File-backed storage fits this first city index; the feed contract permits later storage replacement. No remote acquisition, platform credential, paid call, schedule, production data/schema/deployment or added dependency is authorized by this contract. Restore existing lockfile tooling when absent, without changing manifests or running package scripts. Local fixtures are explicitly synthetic and never the normal account feed. Platform ingestion and real coverage remain required follow-up work, not completed by the index interface.

Demand is the user's explicit default-map correction. Pricing/paywall is unchanged and unvalidated. First distribution is local native evidence and the existing Draft343. Phone152 remains the current installed baseline until the new data route is actually available.

## Boundaries and observable acceptance

- A dedicated public-source manifest must validate in full before serving. Do not query/join places, friend ratings, follows, captures or profiles. No public write/import API.
- Accept only public, recently checked sources with a canonical post URL and a complete reliable venue association; unresolved items do not become pins. Index records are external-public metadata, never user truth.
- Cover imagery needs an explicit author/provider preview grant and an unexpired recognized platform-CDN URL. Covers are post imagery, never claimed as business photography. Missing/blocked images remain missing.
- Fail closed on missing/expired/invalid index and unsupported schema; unavailable service is not a successful empty region. A valid empty viewport is a distinct state.
- Native data is session-scoped/in-memory; reject late responses after query/mode/owner/generation changes. Clear on account change/background/mode exit. No durable photo/post/notes writes while browsing.
- Pins stay geographically anchored and retain click-only pop/wobble. Group posts by exact provider/place identity with consistent venue fields, retaining all authors/sources. Detail shows individual attributed posts and real original links.
- Test public/private rejection, fresh/stale manifests, covers/URLs, viewport/dateline, pagination binding, malformed data, and stale native completion. Verify model logic plus normal-size light/dark native panels, without claiming fixtures are live acquisition.

## Wire contract v1

Authenticated read: `GET /v0/discovery/posts?bbox=west,south,east,north&limit=30&cursor=...`. Verify an account Privy bearer directly before the normal profile-resolving router; discovery must not provision or query a profile, including when the index is unavailable. Guest/share-extension credentials are not accepted.

`bbox` is WGS84, finite, latitude[-90,90], longitude[-180,180], south<north; west>east crosses the dateline. Limit1–50. Cursor binds exact normalized bounds, limit and index revision. Response is `private, no-store` because the app uses its normal account transport; data itself is explicitly public. Missing/configuration/expired index returns503 with `public_discovery_unavailable`; invalid query/cursor returns400. No mutation occurs.

Manifest configuration: `SAVE_PUBLIC_DISCOVERY_INDEX_FILE`. Absent means unavailable, never a seeded sample. Read at most6MiB/5,000 posts. Re-read file changes, reject invalid replacements instead of retaining obsolete data. Strict manifest input keys prevent accidental account/vault exports. Source checks and manifest validity last at most24h; response expires no later than now+5min or the manifest/source deadline.

Manifest:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-14T12:00:00.000Z",
  "expiresAt": "2026-11-15T12:00:00.000Z",
  "coverage": [
    {"platform":"instagram","status":"not_connected"},
    {"platform":"threads","status":"not_connected"},
    {"platform":"xiaohongshu","status":"not_connected"}
  ],
  "posts": []
}
```

Each post has only:

```json
{
  "id": "threads:FIXTUREPOST",
  "platform": "threads",
  "sourceURL": "https://www.threads.com/@fixture/post/FIXTUREPOST",
  "authorName": "Fixture publisher",
  "authorHandle": "fixture",
  "title": "Fixture post title",
  "publishedAt": null,
  "verifiedAt": "2026-11-14T12:00:00.000Z",
  "visibility": "public",
  "locationEvidence": "reviewed_match",
  "cover": null,
  "place": {
    "provider": "apple_maps",
    "providerPlaceID": "fixture-venue",
    "name": "Fixture cafe",
    "address": "1 Fixture Street",
    "latitude": 25.03,
    "longitude": 121.54,
    "coordinateSystem": "WGS84",
    "category": "cafe"
  }
}
```

Source platforms: `instagram`, `threads`, `xiaohongshu`. Post ID is `platform:canonical-post-id`. Source URL must be an actual supported post path, not profile/search/login/short-share URL; normalize Threads.net to Threads.com. Strip tracking query/fragment and reject credentials and access-token-style source URLs. This is canonical attribution, not a claim every platform will open without its own login.

Nullable author name/handle are shown as unavailable, never invented. Title<=160 characters, name<=80, handle<=100. `publishedAt` is the original timestamp if known; never invent it from fetch time. `visibility` must be `public`. Location evidence is `explicit_geotag` or `reviewed_match`; provider is `apple_maps` or `amap`, provider ID/name/address nonempty, normalized coordinateSystem exactlyWGS84, valid/nonzero venue coordinates. The same provider/place ID must have consistent name/address/category/coordinates across records.

Optional cover: `{ "url": "https://...", "expiresAt": "...", "permission": "author" | "provider" }`. Recognized subdomains: `cdninstagram.com`, `fbcdn.net`, `xhscdn.com`, `xiaohongshu.com` image-CDN hosts only. HTTPS, no credentials/local/private hosts, no API access tokens. Unknown/stale/ungranted covers are rejected or omitted explicitly; backend never fetches these URLs. Native image reads must be ephemeral, bounded and cancelable.

Feed response:

```json
{
  "schemaVersion": 1,
  "indexRevision": "sha256-of-normalized-manifest",
  "generatedAt": "2026-11-14T12:00:00.000Z",
  "expiresAt": "2026-11-14T12:05:00.000Z",
  "coverage": [{"platform":"threads","status":"connected","indexedPostCount":1}],
  "posts": [],
  "nextCursor": null
}
```

Feed coverage contains all three platforms with `connected` or `not_connected` and counts from the validated manifest; a platform marked not_connected cannot supply posts. Counts describe this index, not platform-wide coverage. Sort posts by verifiedAt descending then ID ascending, and paginate deterministically. A changed index invalidates old cursors. Nullable cover is optional; every delivered post itself must still validate as public and located.

## Implementation ownership and verification

Backend leaf: new `backend/src/publicDiscovery.ts`, its tests and optional validation CLI only. Controller integrates the read route into server.ts; no existing private feeds change. Native data leaf: `LivePublicDiscoveryData.swift` plus focused tests, matching this wire contract. Controller owns native service/model, map/detail/cover UI, generated project, evidence and Git delivery. Independent Goldfish reviews actual privacy paths/diff/receipts. Leaves do not redelegate or operate devices/build caches.

Native context: existing SAV-E.xcodeproj/SAV-E, SAVE+SAVETests, iOS17; preview stays behind DEBUG+SAVVY_MAIN_APP+SAVVY_DATE_PLAN_PHONE_PREVIEW. Reuse the exclusively leased CityMVP/.build-main cache, generic test-build before one borrowed headless iPhone14Pro/iOS26.5 runtime. Floor10GiB, bounded128MiB task evidence, verify Shutdown. Backend uses existing npm build/test with no live service calls. Hosted CI/production/public acquisition remain separate gates.

## Local implementation and remaining delivery

### Public-card Guide handoff — local implementation

An explicit Plan with friends action opens a separate account-bound list chooser while Explore remains underneath. Reading lists cannot create, join or add anything. The user explicitly chooses an editable list; revalidate membership and candidate expiry before adding a venue-only candidate. Reuse LiveOutingModel's existing ACL/session/payload boundaries. No source post caption, author, imagery, note, rating, personal save or visit crosses this handoff. An existing matching venue completes as already present rather than duplicating it.

The existing list-item POST is not idempotent and assigns its own server item ID. Issue at most one mutation attempt per chooser model. On unknown or acknowledged-but-unconfirmed outcome, offer read-only reconciliation; never automatically retry or claim rollback. Only a fresh ACL-verified list containing the venue enables Open Guide. Navigation then reads that chosen list in Friends mode; adding a candidate does not itself start or fabricate a route. Cancel, inactivity, owner/generation change and expiry fence stale completions. Controller owns chooser/card/root UI; native leaf owns the isolated handoff model/tests; an independent Goldfish checks the frozen diff and real receipts. Same existing Draft343/local delivery boundary; no backend/schema change or phone deployment in this slice.

### Public-source acquisition evidence — 2026-11-15

The bounded official-source review confirms Threads GET keyword_search with q/search_type/fields, and Advanced Access/App Review for threads_keyword_search when searching other people's posts. Without approval, the official sample maintainer says it searches only the authorized user's posts. This is keyword discovery, not verified complete city/bbox coverage. See [Meta request](https://www.postman.com/meta/threads/request/34203612-b3b2c12a-7ce6-4d86-a3c6-6d31e3b66ea1) and [official sample maintainer clarification](https://github.com/fbsamples/threads_api/issues/72).

The rendered request page did not expose fields_threads. A subsequent read through the GitHub connector of [Meta's actual sample implementation](https://github.com/fbsamples/threads_api/blob/main/src/index.js#L1330-L1394) verifies requested username/id/timestamp/media_type/topic_tag/text/permalink/media_url fields, optional before/after/limit/since/until/media_type/author_username, and response.data.data with optional paging next/previous links. The [official collection](https://github.com/fbsamples/threads_api/blob/main/postman/threads-api.postman_collection.json) also selects location_id for general post reads and location name/address/city/country/latitude/longitude via GET /{location_id}; it contains no actual response body proving returned types or coverage. These are static sample contracts, not live acceptance or preview reuse grants. The Graph numeric id is not this index's canonical ID: derive the latter from the verified permalink path. Coordinate system and provider-place association still need proof; do not invent a location or fill cover.permission=provider from an image URL. Configured credentials, scopes, HTTP200 or own-post results cannot by themselves establish cross-author public access.

Instagram's detailed public discovery contract was not independently verified because the official page returned429. Xiaohongshu's readable official material describes merchant authorization and ecommerce application categories, which does not establish arbitrary public-note search: [authorization](https://open.xiaohongshu.com/document/developer/file/38), [application categories](https://open.xiaohongshu.com/document/developer/file/33). No account credential, app approval, token call, live platform ingestion or preview grant was verified. The first proposed adapter remains conditional on approved Threads access and an actual finite read proving post identity/source/venue fields; no reliable location means no pin, and no grant means cover:null. These sources do not justify a claim of all public posts.

The local preview wires Explore as default, Mine/Friends retained, scoped viewport requests, explicit pagination, expiry/session/query fences, grouped public-source pins and attributed post cards. Post covers use an ephemeral bounded image reader with no cookies, credentials, disk cache or redirects; missing photos remain missing. Explicit confirmation exports only venue identity and the selected original URL, without caption, author memory, ratings or photos. Public cards also offer the direct venue-only shared-list chooser described above; it does not require a personal save, and only a separate Open Guide action navigates to that freshly reread list for stop selection and planning.

New files: publicDiscovery.ts/tests validate/read the operator artifact; publicDiscoveryEndpoint.ts/tests authenticate without profile provisioning; LivePublicDiscoveryData.swift/tests own native validation and exact venue grouping; LivePublicDiscoveryModel.swift/tests fence publication; LivePublicDiscoveryViews.swift presents source-specific imagery and attribution. Modified server.ts routes before profile resolution; SupabaseService uses the existing owner-bound transport; root/map/projection files integrate the lens. This is a source implementation, not proof of actual external acquisition or running hosted routes.

Verification discovered missing backend dependencies. Restoring the unchanged package-lock with npm ci --ignore-scripts added no dependency or manifest change; the complete backend suite then passed906 cases:837 passed,69 skipped,0 failed. The initial native test-build failed new fixture actor isolation and an optional note assertion; both were repaired, and later generic flagged test-builds passed. Runtime/visual results are recorded below when completed. Evidence directory public-discovery-153 is the task label, not an installed build claim; phone152 remains unchanged.

Final local runtime: all1,999 SAVETests executed,1,995 passed,4 expected skips,0 failures. This includes nine discovery-data tests, four discovery-model tests and the additional summary/detail render case. Four393×852pt normal-size light/dark component images were exported and inspected; they contain explicit test-only sources without images and do not establish actual provider coverage, full-root interactions or image-loading performance. The raw passed result bundle was archived and CRC-verified before removing this task's raw duplicate. Borrowed simulator Shutdown was independently read back. Post-runtime space initially fell below10GiB. After it recovered above the floor, a separate exclusive build lease completed the ordinary-main generic simulator build successfully, without booting a device. Hosted required CI/full integration/0.90 visual acceptance, real acquisition, public-card-to-Guide shortcut and real phone interaction remain pending. Actions stays disabled, Draft343 stays unready for merge, and no phone/backend deployment occurred.


### Guide chooser verification — 2026-11-15

The Guide shortcut is now implemented locally by LivePublicGuideModel/LivePublicGuideChooser and the root handoff. The model reuses existing list/roster ACL snapshots, excludes optional friends-feed reads, and transmits only a canonical venue candidate under the current owner/session TaskLocal. Cached viewer roles, permission downgrade/revocation, duplicate venue, lost acknowledgement, failed confirmation, cancellation, inactivity and expiry are covered. There is no backend change, global server idempotency claim or automatic navigation/save/visit.

Both generic flagged test-builds and all2,009 SAVETests passed (2,005passed,4expected skips,0failures). Visual inspection then caught a test-fixture lifecycle problem: the light window deactivated a shared chooser model, so its original dark capture was not a ready chooser. A fresh model per theme and required ready/list-count/no-write assertions corrected that verifier, alongside a full-width content layout. The latest flagged rebuild and all nine affected surface tests pass; unchanged model inputs retain their full-suite evidence. The authoritative six normal393×852pt light/dark captures are UI-final-chooser and UI-final-discovery in ignored Evidence/public-guide-154. Older UI-chooser captures are superseded diagnostics, not acceptance. Full and focused raw result bundles share the CRC-verified archive; their task-owned raw duplicates were removed. The borrowed simulator is Shutdown. Ordinary-main generic build also passes. Evidence154 is a task label; phone build152 is unchanged.

The source-level nested-sheet/dismissal/selected-list handoff is independently inspected, but its actual full-root interaction remains unproven by component renders. Real platform acquisition, approved cross-author access, place matching, imagery grants/coverage, device interaction and required hosted CI/full integration/0.90 visual acceptance remain pending. UI-sdk/Modern Web Guidance are web-only here; native SwiftUI and current brand tokens remain the implementation route.
