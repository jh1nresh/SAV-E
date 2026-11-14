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

The local preview wires Explore as default, Mine/Friends retained, scoped viewport requests, explicit pagination, expiry/session/query fences, grouped public-source pins and attributed post cards. Post covers use an ephemeral bounded image reader with no cookies, credentials, disk cache or redirects; missing photos remain missing. Explicit confirmation exports only venue identity and the selected original URL, without caption, author memory, ratings or photos. Saving through the canonical path precedes the existing Friends/Guide flow; a direct public-card-to-Guide list chooser is not implemented yet.

New files: publicDiscovery.ts/tests validate/read the operator artifact; publicDiscoveryEndpoint.ts/tests authenticate without profile provisioning; LivePublicDiscoveryData.swift/tests own native validation and exact venue grouping; LivePublicDiscoveryModel.swift/tests fence publication; LivePublicDiscoveryViews.swift presents source-specific imagery and attribution. Modified server.ts routes before profile resolution; SupabaseService uses the existing owner-bound transport; root/map/projection files integrate the lens. This is a source implementation, not proof of actual external acquisition or running hosted routes.

Verification discovered missing backend dependencies. Restoring the unchanged package-lock with npm ci --ignore-scripts added no dependency or manifest change; the complete backend suite then passed906 cases:837 passed,69 skipped,0 failed. The initial native test-build failed new fixture actor isolation and an optional note assertion; both were repaired, and later generic flagged test-builds passed. Runtime/visual results are recorded below when completed. Evidence directory public-discovery-153 is the task label, not an installed build claim; phone152 remains unchanged.

Final local runtime: all1,999 SAVETests executed,1,995 passed,4 expected skips,0 failures. This includes nine discovery-data tests, four discovery-model tests and the additional summary/detail render case. Four393×852pt normal-size light/dark component images were exported and inspected; they contain explicit test-only sources without images and do not establish actual provider coverage, full-root interactions or image-loading performance. The raw passed result bundle was archived and CRC-verified before removing this task's raw duplicate. Borrowed simulator Shutdown was independently read back. Post-runtime space initially fell below10GiB. After it recovered above the floor, a separate exclusive build lease completed the ordinary-main generic simulator build successfully, without booting a device. Hosted required CI/full integration/0.90 visual acceptance, real acquisition, public-card-to-Guide shortcut and real phone interaction remain pending. Actions stays disabled, Draft343 stays unready for merge, and no phone/backend deployment occurred.
