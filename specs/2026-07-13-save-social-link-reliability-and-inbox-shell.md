# SAV-E Social Link Reliability and Inbox-First Shell

Created: 2026-07-13
Issue: #528
Status: implemented

## Decision

SAV-E should launch into a private place-memory Inbox, not a map with a
persistent drawer. The map remains a first-class output for confirmed places.

This slice does not turn SAV-E into a generic save-anything app. Recipes,
articles, books, products, events, and videos need their own content schema,
retrieval evals, and customer proof before they become product scope.

```text
social or map link
-> captured source
-> source-only clue or review candidate
-> user decision
-> confirmed Map Stamp
```

## Why Albo is a useful reference

Albo's current public product uses a save-first library with visual content
cards, content categories, collections, Ask, and a map. The reusable lesson is
the information architecture: saved content is the home surface and the map is
one way to use place saves. Removing the map is not the lesson.

Public references: [Albo website](https://albo.inc/) and
[App Store listing](https://apps.apple.com/us/app/albo-save-organize/id6578421992).

SAV-E should not copy Albo's broad content promise yet. SAV-E's stronger wedge
is evidence-backed place recovery and an explicit review boundary.

## Reliability evidence

### Deterministic iOS suite

Command:

```bash
scripts/xcodebuild-clean.sh \
  -project SAV-E.xcodeproj \
  -scheme SAV-E \
  -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  test -only-testing:SAVETests/SocialPlacePipelineTests
```

Receipt: 114 tests passed, 0 failed.

Named test coverage is uneven. Counts overlap when one test names more than one
platform.

| Platform / adapter | Named tests | Confidence from repo evidence | Current boundary |
| --- | ---: | --- | --- |
| Instagram | 41 | Medium | Strong fixture coverage; live metadata remains intermittent. |
| TikTok | 2 | Low | Adapter contract and list OCR fixture; no current real-link fixture. |
| Xiaohongshu | 6 | Low | Correctly preserves blocked links as source-only; public metadata is unreliable. |
| Douyin | 8 | Low-medium | Good share-text/list safety fixtures; live short-link recovery is blocked. |
| Dianping | 2 | Low-medium | Keyword extraction is covered; public-link availability is not proven. |
| Google Maps | 5 | High for structured URLs | Structured place/query URLs are deterministic; private saved-list shells stay unresolved. |
| Amap | 4 | Medium-high for structured links | Place/deep-link parsing and coordinate provenance are covered. |
| Baidu Maps | 2 | Medium for structured links | Deep-link/fallback behavior is covered. |
| Threads | 0 | Unknown | URL classification exists, but there is no parser regression fixture. |
| YouTube | 0 | Unsupported | No content adapter or place extraction fixture. |
| Facebook | 0 | Unsupported | No content adapter or place extraction fixture. |
| Pinterest | 0 | Unsupported | Share UI labels the source, but the app parser has no dedicated adapter. |
| Reddit | 0 | Unsupported | Generic URL only. |

### Backend suite

Command:

```bash
cd backend && npm test
```

Receipt: 222 tests passed, 0 failed.

These tests prove normalization, safety gates, receipts, metadata parsing, and
injected recovery behavior. They do not prove that a social platform will
serve public metadata in production at a particular moment.

### Production capability probe

Endpoint checked:

```text
GET https://wanderly-api-production.up.railway.app/health/source-recovery
```

Observed on 2026-07-13:

```text
ready: true
keyframe extraction: disabled
OCR: disabled
ASR: disabled
external rubric: ready
```

Production can use public metadata and search recovery, but it is not currently
doing server-side video-frame OCR or speech transcription.

### Live source probes

These probes are diagnostic, not permanent fixtures:

- Instagram Reel `DZpGkJ-tK5n`: one request failed to fetch; a subsequent
  request obtained public metadata and the correct address, but selected
  `地址：` as the candidate name. This is an entity-binding defect.
- Xiaohongshu short link `7FgwQfDuTc4`: blocked redirect; preserved as
  source-only with no invented place.
- Douyin short link `1GiTQ8dM5U8`: blocked redirect; preserved as source-only.
  The backend also labels this path as `web_url`, showing a source-type coverage
  gap.

## Product implications

SAV-E must never communicate that all supported platform links are equally
analyzable. The user-facing states should be:

```text
Ready to review
Needs another clue
Source saved
Confirmed Map Stamp
```

"Source saved" is a valid result. It keeps the original link retrievable and
allows later enrichment without polluting the map.

## P1 app shell

Default authenticated entry:

```text
Memory Inbox
  Needs Review
  Source-only clues
  Recent Map Stamps
  Ask SAV-E entry
  Open Map entry
```

Map workspace:

```text
Confirmed stamps on Map
  Existing command drawer
  Explicit return to Inbox
```

## Acceptance criteria

1. Authenticated users land on a full-screen Inbox, not a map background.
2. Needs Review and source-only clues are visibly separate.
3. A candidate opens the existing evidence and correction detail flow.
4. Recent confirmed places are visible without opening the map.
5. Map remains available as a secondary workspace and can return to Inbox.
6. No weak candidate becomes a confirmed map pin.
7. Existing parser and backend suites remain green.
8. Phone and iPad screenshots show readable, non-overlapping layouts.

## Out of scope

- Generic content models for recipes, books, products, articles, or movies.
- A cross-content recommendation engine.
- Parser fixes found by the live probes.
- Backend schema or production capability changes.
- Auth, paywall, TestFlight, or App Store metadata changes.

## Follow-up reliability work

1. Add a live-link canary set with redacted/stable public samples and daily
   receipts. Do not make CI depend on third-party uptime.
2. Fix Instagram label/address entity binding.
3. Include Douyin in backend social URL classification.
4. Add real TikTok and Threads fixtures.
5. Decide whether production video keyframe/OCR is worth its cost before
   enabling it.
