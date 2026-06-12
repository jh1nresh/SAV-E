# SAV-E China social source adapters: XHS, Douyin, Dianping

> Created: 2026-06-11  
> Repo: `wanderly-ios`  
> Status: source-adapter capability note / PM-gate input

## Trigger examples

User supplied:

```text
http://xhslink.com/o/7FgwQfDuTc4
http://dpurl.cn/IFoOLolz

9.41 复制打开抖音，看看【金贵七七（环游中国版）的作品】五一大家不要放过武汉！三刷武汉后从20+家美食里筛... https://v.douyin.com/1GiTQ8dM5U8/ 05/20 JIi:/ f@o.Qk :9pm
```

Local fetch evidence:

- XHS short link resolves to:
  `https://www.xiaohongshu.com/discovery/item/6a220d480000000007012ad0?...`
- XHS public HTML title is only generic `小红书`; no readable caption/title/place evidence was exposed in public fetch.
- Dianping short link resolves to:
  `https://m.dianping.com/feeddetail/466776750?...`
- Dianping public HTML exposes useful metadata:
  - title / og:title: `青岛崂山📍住到了人生酒店！`
  - keywords includes: `奢海陌野民宿`
  - description includes travel/hotel evidence.
- Douyin noisy share text contains an embedded short URL:
  `https://v.douyin.com/1GiTQ8dM5U8/`
- That Douyin short URL resolves to:
  `https://www.iesdouyin.com/share/video/7628919504407399680/...`
- Douyin public metadata exposes useful but list-level text:
  - title: `五一大家不要放过武汉！三刷武汉后从20+家美食里筛出这篇攻略 #青年创 - 抖音`
  - description: `五一大家不要放过武汉！三刷武汉后从20+家美食里筛出这篇攻略 ... #武汉 ... - 金贵七七（环游中国版）...`

## Mainland app share-text normalization

China/mainland apps often share noisy text, not just a clean URL:

```text
9.41 复制打开抖音，看看【creator 的作品】caption... https://v.douyin.com/<code>/ 05/20 JIi:/ f@o.Qk :9pm
```

The adapter must treat this as a source bundle:

```text
rawShareText
→ extract first/all embedded URLs
→ preserve pre/post URL caption text as evidence
→ resolve short URL
→ merge resolved public metadata + raw share caption
→ classify source shape
```

Rules:

- Do not require the shared text to be a bare URL.
- Strip app-open boilerplate such as `复制打开抖音`, `看看【...的作品】`, random share tokens, timestamps, and invitation codes from candidate extraction, but preserve it in diagnostic/source evidence if useful.
- The text before the URL can be useful caption evidence. For the supplied Douyin share, `武汉`, `20+家美食`, `美食攻略`, and the creator name are useful source-level clues.
- If the public metadata says `20+家美食`, treat it as a multi-place/list source, not one place.
- A list source with no individual visible place names should become SourceOnly or `multi_place_list_needs_screenshot`, asking for screenshots/keyframes/caption text, not one fake Wuhan restaurant.

## Current repo capability snapshot

Code already has more than zero support for XHS/Douyin:

- `SAV-E/Services/SocialLinkReviewCandidateService.swift`
  - XHS source-only / note-id handling.
  - XHS readable-caption path can become Review Candidate.
  - Douyin descriptor / recovery query support.
  - China resolver path using Google + AMap + Baidu provider abstractions.
- `SAV-EShared/SocialPlaceParser.swift`
  - TikTok/Douyin-style source adapter and social evidence parser.
- `SAV-EShareExtension/ShareViewController.swift`
  - Recognizes XHS and Douyin domains in source labels / URL activation helpers.
- `Tests/SocialPlacePipelineTests/SocialPlacePipelineTests.swift`
  - XHS URL-only should become source-only, not fake place.
  - XHS caption metadata with `📍` + address can become Review Candidate.
  - Douyin food-list fixture can produce multi-place candidates without fake coordinates.
  - AMap/Baidu resolver tests preserve coordinate-system provenance.

But Dianping / 大众点评 is not yet a first-class adapter in the inspected code.

## Correct product interpretation

### Xiaohongshu / XHS

Current expected behavior for URL-only XHS:

```text
resolve short/canonical URL
→ extract note id if available
→ if public metadata is generic/blocked, save source-only clue
→ ask user for screenshot, copied caption, or map link
```

This is correct and safe. It should not hallucinate a place from the XHS URL alone.

For the supplied XHS URL, public fetch exposed the canonical note id but not readable caption/place metadata. So SAV-E should create a source-only clue and ask for screenshot/caption/map link.

To get Hermes-like XHS analysis, SAV-E needs stronger evidence capture:

```text
XHS link + screenshot/OCR or copied caption
→ parser extracts venue/address clues
→ AMap/Baidu/Google provider resolver
→ Review Candidate
→ user confirmation
→ Map Stamp
```

### Douyin / 抖音

Douyin is closer to workable than XHS when public metadata/caption is exposed. Existing tests cover Douyin-style food lists.

Expected behavior:

```text
resolve short link
→ inspect public metadata/caption/OCR
→ if multi-place list, create multiple Review Candidates
→ preserve page/image ranges as evidence
→ no fake coordinates
```

Need real-device/share-link fixtures to verify actual installed-app behavior for current Douyin links.

### Dianping / 大众点评

Dianping should be added as a first-class adapter.

Reason: the supplied `dpurl.cn` link exposed useful public metadata with likely place identity in `keywords`:

```text
title: 青岛崂山📍住到了人生酒店！
keywords: 奢海陌野民宿
site: 大众点评
```

Expected behavior for this source:

```text
dpurl.cn short link
→ resolve m.dianping.com/feeddetail/<id>
→ read og:title / og:description / keywords / og:image
→ extract likely business/place name from keywords or embedded feed data
→ run China resolver through AMap/Baidu/provider chain
→ create Review Candidate, not Map Stamp
```

## Why current app still feels like it cannot analyze these well

1. XHS URL-only often gives generic/blocked metadata. SAV-E correctly cannot infer place without screenshot/caption/map link.
2. Douyin support exists in parser/tests, but may depend on public metadata availability and installed share-extension evidence.
3. Dianping has useful public metadata but lacks a dedicated adapter, so it may fall through generic social/source parsing.
4. Mainland China place resolution needs AMap/Baidu keys/backend proxy configured; otherwise candidates may stop at Review/source-only.
5. User-facing UI likely needs clearer state: `Saved source, need screenshot/caption` vs `Possible place found` vs `Ready to review`.

## Server-side media/keyframe path

For Douyin and some other video sources, SAV-E can sometimes avoid asking the user for screenshots by creating its own screenshots from public media:

```text
resolve short link
→ parse SSR JSON / public page metadata
→ if `video.play_addr.url_list` or public player URL is exposed, download bounded video server-side
→ sample keyframes every N seconds and at scene changes
→ OCR keyframes for Chinese text overlays
→ optionally ASR the audio when place names are spoken but not written
→ classify single-place vs multi-place list
→ create Review Candidates or SourceOnly/list-needs-more-evidence
```

Concrete supplied Douyin example:

- `v.douyin.com/1GiTQ8dM5U8` exposed an `iesdouyin.com/share/video/7628919504407399680` SSR payload.
- SSR payload included `video.play_addr.url_list`, allowing a public MP4 download in this environment.
- Downloaded video was about 123 MB and 312 seconds.
- Keyframe sampling surfaced visible place/list clues including:
  - `一席之地`
  - `三眼桥过早` / `三眼桥北路`
  - `糯米包油条` / `三眼桥北路`
  - `万松园` / `江汉区万松街万松园`
  - `甜品店` / `江汉区江汉路步行街附近`
  - `夜市宵夜街` / `汉中街道长堤街`
  - dish/category clues like `藕汤`, `煎饺`, `糯米包油条`, `抽干面`

Important boundary: this does not guarantee all restaurants. If the video hides shop names, only speaks names in audio, requires login, or blocks media URLs, SAV-E must fall back to user screenshot/caption/map link. Media/keyframe extraction should be server-side/async, bounded by file size/time, and produce an evidence receipt.

## MVP recommendation

Add adapters in this order:

1. **Douyin server-side keyframe/OCR path for public video links** — this can reduce screenshot asks when the page exposes public MP4/keyframes.
2. **Dianping adapter** — high ROI for China restaurant/hotel links because public metadata is exposed.
3. **XHS source-only recovery UI** — already correct as source-only, but make the user CTA better: add screenshot / paste caption / share map link.
4. **Douyin real-link fixture hardening** — verify actual public metadata/media on current short links and keep multi-place list behavior.
5. **AMap/Baidu provider config check** — ensure China resolver works in app/backend, not just test stubs.

## Acceptance criteria for Dianping PR

- `dpurl.cn` and `m.dianping.com/feeddetail/<id>` are detected as Dianping sources.
- Short link resolves to canonical URL.
- Metadata parser extracts:
  - feed id
  - title
  - description
  - keywords / likely business name
  - image URL if available
- Business name from `keywords` outranks generic title like `住到了人生酒店`.
- Candidate stays Review Candidate until provider resolver/user confirmation.
- AMap/Baidu/Google refinement is attempted for Chinese place clues.
- If resolver fails, candidate still preserves Dianping source/evidence and asks for confirmation or map link.

## Test fixtures to add

- XHS supplied URL shape: canonical id extracted but generic metadata => source-only.
- Dianping supplied URL shape: `奢海陌野民宿` from keywords => Review Candidate.
- Dianping generic title should not become the place name if keywords/business field exists.
- Dianping provider match must preserve AMap/Baidu coordinate provenance.
- Douyin noisy share-text fixture should extract the embedded `v.douyin.com` URL and preserve raw caption clues.
- Douyin `20+家美食` metadata should be classified as a multi-place/list source needing screenshots/keyframes/caption, not a single Wuhan place.
- Douyin real short-link fixture with public metadata should either become multi-place Review Candidates when individual place names are visible, or source-only/list-needs-evidence with clear missing evidence.
