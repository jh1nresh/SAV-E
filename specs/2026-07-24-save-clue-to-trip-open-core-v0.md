# SAV-E Clue-to-Trip Open Core v0

Date: 2026-07-24
Status: implementation spec
Repo: `/Users/jhinresh/projects/sav-e`

## Decision

The portable product workflow is:

```text
public clue or link
-> place candidates with evidence
-> user-confirmed Place Identity / Map Stamp
-> bounded related public-source discovery
-> reviewed Place Source Pack
-> planner-neutral Trip Manifest
-> TREK or another planner adapter
```

The workflow may later become an open-source agent skill, CLI, MCP server, and
JSON contract. The first implementation stays inside SAV-E so real fixtures can
stabilize the contract before it is extracted.

The repository is publicly visible but does not currently contain a declared
open-source license. Public visibility is not an open-source grant. Selecting
and adding a license is a separate founder/legal gate before describing the
project as open source or publishing a reusable package.

“Find all social posts” is not a supported promise. Private, deleted,
login-gated, non-indexed, geographically restricted, or platform-blocked
content cannot be exhaustively discovered. The product promise is:

> Search supported public sources, rank likely same-place results, and report
> the platforms and queries that succeeded, failed, or remain unsupported.

## Product boundary

SAV-E remains the place-memory and confirmation system:

- parse shared links and text;
- retain weak evidence as SourceOnly or Review;
- confirm exact place and branch identity;
- store Map Stamps, evidence, and user decisions.

TREK remains the downstream trip-planning surface. SAV-E exports only confirmed
Map Stamps or a planner-neutral manifest. This slice does not copy, vendor, or
modify TREK source code.

Related-source discovery begins only after a place belongs to a Privy-authenticated
account. Guest sessions are not allowed on this paid-provider path. Search
results never create places, Map Stamps, or Trip Stops.

## Customer-paid job

> Turn a messy travel or food clue into a confirmed place with a small,
> attributable set of useful related public sources, then make that place ready
> for itinerary planning.

The value is not raw search volume. It is branch-correct evidence with an honest
coverage receipt.

## Open-core boundary

Eligible for a future permissive open-source package:

- `PlaceIdentity`, `RelatedPlaceSource`, `PlatformCoverage`, `PlaceSourcePack`,
  and planner-neutral manifest schemas;
- deterministic query fanout, URL normalization, duplicate handling, ranking,
  and receipts;
- provider adapter interface;
- Agent Skill, CLI, and MCP wrappers;
- fixture/evaluation harness.

SAV-E hosted/private responsibilities:

- user authentication and owner-scoped storage;
- provider credentials, quotas, billing, and rate limits;
- private captures, screenshots, OCR/ASR, decisions, and receipts;
- paid or contract-bound provider adapters;
- iOS UI, sync, Map Stamp, friends, and account data.

Planner implementations remain separate dependencies. An open skill can emit a
Trip Manifest or call an explicitly configured planner adapter; it does not
relicense or bundle TREK.

## P1 independently testable slice

Add an authenticated SAV-E backend endpoint:

```http
POST /v0/places/:id/related-sources
```

Request:

```json
{
  "platforms": ["instagram", "tiktok", "youtube", "xiaohongshu"],
  "max_results_per_platform": 5
}
```

Response:

```json
{
  "place": {
    "id": "uuid",
    "name": "Confirmed venue",
    "address": "Confirmed address",
    "latitude": 0,
    "longitude": 0
  },
  "sources": [
    {
      "platform": "instagram",
      "url": "https://www.instagram.com/...",
      "title": "Result title",
      "snippet": "Bounded public-search snippet",
      "query": "site:instagram.com ...",
      "relation": "same_place",
      "match_confidence": 0.82
    }
  ],
  "coverage": [
    {
      "platform": "instagram",
      "status": "searched",
      "queries": ["site:instagram.com ..."],
      "result_count": 1
    }
  ],
  "receipt": {
    "source_boundary": "public_web_index",
    "requested_platforms": ["instagram"],
    "searched_platforms": ["instagram"],
    "failed_platforms": [],
    "raw_result_count": 3,
    "independent_result_count": 1,
    "missing": []
  }
}
```

P1 uses the existing bounded public-search fetcher. Before any public query, the
backend re-resolves the saved `google_place_id` through the existing Google
Places backend credential and replaces client-authored name, address, category,
and coordinates with that authoritative public-venue identity. Missing,
residential, malformed, or unverifiable identities fail closed. No new social
provider credential or dependency is added; the provider-neutral source
contract remains the artifact under test.

Supported v0 platform identifiers:

- `instagram`
- `tiktok`
- `youtube`
- `xiaohongshu`
- `douyin`
- `threads`
- `x`

## Behavioral invariants

1. The endpoint requires a verified Privy bearer account and only accepts an
   owner-scoped confirmed place; guest tokens are rejected.
2. Search starts from canonical place identity. A source link cannot replace or
   mutate that identity.
3. Every query is platform-bounded with an approved public domain.
4. Returned URLs must belong to the requested platform.
5. Exact and tracking-parameter URL duplicates collapse deterministically.
6. Client aliases are rejected in v0. Queries use only the Google-verified
   canonical venue name. A result is `same_place` only when it contains that
   canonical name plus branch-strength street or full-address evidence.
   Name-only, city-only, or district-only results remain `mentions_place`;
   explicit branch conflicts are rejected.
7. Generic platform pages, search pages, and empty URLs are rejected.
8. A failed platform produces coverage status and a blocker; it does not erase
   successful platforms.
9. Snippets are bounded. Full third-party posts, private payloads, cookies, and
   user secrets are never stored or returned.
10. No result is directly saved to places, claims, Map Stamps, Trip Stops, or
    TREK.
11. Discovery is limited to public venues. Person, profile, home-address,
    private-residence, stalking, or surveillance queries are rejected before
    public search. Stored client fields are not accepted as public-venue proof.
12. Owner-visible receipts may contain bounded queries and source URLs. Any
    future public telemetry must use a separately redacted projection without
    raw URLs, coordinates, captions, or user text.
13. Search fanout uses at most three concurrent requests and a 20-second
    aggregate deadline. Each fetch retains the existing DNS, redirect, timeout,
    and response-size protections.
14. A request accepts at most seven platforms, two query variants per platform,
    five inspected results per query, and five returned sources per platform
    (35 returned sources maximum).
15. Each account receives six related-source requests per ten-minute process
    window. Verified/rejected Google venue details are coalesced and cached for
    24 hours with a bounded 500-entry cache; transient failures are not cached.

## Failure taxonomy and fixtures

Freeze fixtures before paid-provider adoption:

- exact place and city match;
- exact place and address match;
- same name in the wrong city;
- branch name collision;
- generic list or platform landing page;
- duplicated URL with tracking parameters;
- multilingual canonical display-name match;
- missing URL;
- platform host mismatch;
- login wall or provider failure;
- sparse result that must abstain;
- commercial/affiliate source with otherwise valid identity.

Initial provider bakeoff should add 20–30 real confirmed places across Taipei,
Tokyo, and Shanghai. Compare:

- same-place precision at five;
- useful-source rate;
- independent results after dedupe;
- platform coverage and honest blocker reporting;
- latency and cost;
- stale/deleted URL rate.

Provider activation requires a frozen held-out set and strict improvement over
the public-search baseline. Each provider also requires a recorded terms,
retention, attribution, deletion, region, cost, and kill-switch review.

## Acceptance scenarios

### Valid exact-branch result

Given an owned confirmed place and a result containing its name and city or
address, the worker returns a normalized `same_place` source and a searched
coverage entry.

### Name-only result

Given a result containing the place name but no location clue, the worker may
return `mentions_place` with lower confidence. It cannot become `same_place`.

### Wrong platform

Given an Instagram query whose result URL resolves outside approved Instagram
hosts, the result is rejected.

### Duplicate source

Given two URLs that differ only by known tracking parameters or fragments, one
canonical source remains and the receipt counts the raw and independent totals.

### Provider failure

Given one platform search failure and one successful platform, the successful
source remains. Coverage identifies the failed platform without exposing raw
provider errors or secrets.

### Ownership failure

Given an unknown or another user’s place ID, the endpoint returns the existing
owner-scoped `404` behavior and does not run search.

### Public-venue verification failure

Given a saved place without a Google Place ID, a residential/address-only
Google type, or unavailable Google verification, the endpoint fails before
public search. Client-authored name, category, address, and coordinates cannot
substitute for provider-confirmed public identity.

## Out of scope

- logged-in Instagram, TikTok, Xiaohongshu, or other browser automation;
- browser-cookie extraction, anti-detection, CAPTCHA bypass, or rate-limit
  evasion;
- exhaustive “all posts” claims;
- new paid social-search provider keys or production provider activation;
- media downloads, comments, creator profiling, or full-post archiving;
- persistence of proposed source edges;
- iOS UI in this P1;
- related-place recommendations;
- itinerary optimization or embedded TREK code;
- public repository creation or package publication.

## Implementation plan

1. Add a pure `relatedPlaceSources` module with contracts, platform registry,
   query fanout, normalization, ranking, dedupe, coverage, and receipts.
2. Add a fail-closed Google Places Details verifier that converts the owned row
   into an authoritative public-venue identity before discovery.
3. Reuse the existing safe public-search fetch and DuckDuckGo parser through a
   small exported helper rather than introducing another crawler.
4. Add the owner-scoped route to `server.ts`.
5. Add valid, malformed, residential, branch-collision, dedupe, host-mismatch,
   partial-failure, bounded-concurrency, and deadline tests.
6. Document the route and run focused plus full backend checks.

## Verification

```bash
cd backend
npm run build
node --test dist/relatedPlaceSources.test.js dist/sourceSearchWorker.test.js
npm test
npm run check:source-recovery
git diff --check
```

Security receipt:

- Scope: authenticated owner-scoped place lookup plus public-search result
  normalization and fixed-host Google public-venue verification.
- Reachable path: `POST /v0/places/:id/related-sources`.
- Required checks: SSRF protections remain in the existing fetcher; platform
  host allowlists; fixed Google Places host and bounded response; request bounds;
  Privy-only access; owner quota and bounded verification cache; aggregate
  deadline; bounded snippets; private no-store response; no credential logging;
  no direct persistence.

## Distribution and pricing gate

P1 is an internal product proof, not a paid feature. Record request count,
coverage, latency, and usefulness before choosing a pricing model.

The first public distribution format, after held-out success, is a GitHub
repository containing the contracts, fixture harness, and agent-callable
Skill/CLI/MCP wrapper. Hosted provider access may later use credits, but no
pricing or paywall is added before measured provider cost and user usefulness.

## Done when

- the owner-scoped endpoint returns deterministic sources, coverage, and a
  receipt;
- focused malformed and valid fixtures pass;
- existing source recovery remains green;
- no new social-search credential, new dependency, schema mutation, direct save,
  or TREK source copy is introduced;
- the diff passes review and ships as one atomic PR.

## P2: confirmed Map Stamp related-source review

The next independently testable slice exposes P1 from the confirmed Map Stamp
detail surface. Discovery is explicit and read-only:

```text
confirmed Map Stamp
-> user taps Find related sources
-> authenticated owner-scoped request
-> candidate links + per-platform coverage receipt
-> user may open a public link
```

P2 does not persist a source, change the Map Stamp, or add anything to a Trip.
The App Review demo guest cannot call this account-only endpoint.

### P2 acceptance scenarios

1. A confirmed Map Stamp shows one `Find related sources` action. Opening the
   detail does not start a request.
2. One tap sends the Map Stamp UUID to
   `POST /v0/places/:id/related-sources` with the seven supported platform
   identifiers and at most three results per platform.
3. Loading, populated, honest-empty, partial-coverage, and retryable-error states
   are visually distinct. Cancellation from leaving the surface is not shown as
   an error.
4. Every result remains labeled as a candidate. `same_place` and
   `mentions_place` are distinguishable without implying user confirmation.
5. Coverage shows which supported platforms were searched, partially searched,
   or failed. A successful platform remains visible when another platform fails.
6. A source URL opens only after the user taps it. The iOS model independently
   requires an allowlisted platform host over HTTPS.
7. `400`, `401/403`, `404`, `409`, `429`, `503`, network, and malformed-response
   failures map to bounded localized guidance. Raw backend/provider bodies are
   never rendered.
8. The view does not call a guest-token path, mutate persistence, create a
   Review Candidate, change a Map Stamp, or add a Trip Stop.

### P2 Xcode context receipt

```text
Product/repo: SAV-E / /Users/jhinresh/projects/sav-e
Platform: iOS SwiftUI with existing Node backend
Project: SAV-E.xcodeproj (project.yml is the XcodeGen source)
Scheme / target: SAV-E / SAVE
Deployment target: iOS 17.0
Verification tier: generic build during implementation, one final UI runtime
Generic destination: generic/platform=iOS Simulator
Runtime device: iPhone 16 Pro, iOS 26.5, FA3C4BA8-6E62-4F31-84DC-10787DF785FA
Simulator reason: prove the explicit CTA and candidate/coverage presentation
Canonical DerivedData: /Users/jhinresh/Library/Developer/Xcode/DerivedData/SAV-E-ahydqktpduridpbzrzurshjbxqni
XcodeBuildMCP: unavailable; use scripts/xcodebuild-clean.sh
Primary route: swift-xcode-workflow + swiftui-ui-patterns
```

### P2 verification

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath '/Users/jhinresh/Library/Developer/Xcode/DerivedData/SAV-E-ahydqktpduridpbzrzurshjbxqni' \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build

scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=FA3C4BA8-6E62-4F31-84DC-10787DF785FA' \
  -derivedDataPath '/Users/jhinresh/Library/Developer/Xcode/DerivedData/SAV-E-ahydqktpduridpbzrzurshjbxqni' \
  -only-testing:SAVETests \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test
```

The real-place precision bakeoff remains the promotion gate after P2. It needs a
frozen held-out fixture set and must not be replaced by UI screenshots or mock
response volume.
