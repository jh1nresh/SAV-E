# Differential Security Review — PR #402 (`claude/eager-dubinsky-8c2061` vs `main` @ fc0dc73c)

> Date: 2026-06-12
> Scope: `git diff main...HEAD` (7 commits: 9d38cce8, 06cec1d7, adc03ca6, 7b00fdaf, 935bf378, 9eec279f, bfaf16c2)
> Method: risk-first triage per pre-agreed plan; blame-checked removed/changed guard lines against #398–#401; verified guardrail invariants in code, not comments.

## Verdict

No HIGH findings. **1 MEDIUM, 2 LOW, 5 INFO.** The evidence-bound guardrails were **not** loosened — every new parse path (text-share normalizer, western map links, onboarding first clue) terminates in a `PendingReviewCandidate` that requires explicit user action to become a Map Stamp. The MEDIUM is an input-validation gap in the new Apple Maps link adapter (NaN/Inf/out-of-range coordinates).

---

## Findings

### M-1 (MEDIUM) — Apple Maps `ll` parser accepts NaN / Infinity / out-of-range coordinates

**File:** `SAV-E/Services/SocialLinkReviewCandidateService.swift`, `westernMapLinkMatch(in:)`, Apple Maps branch (~line 930–940 post-diff):

```swift
let parts = ll.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
...
guard isUsableCandidateName(name), parts.count == 2, parts[0] != 0 || parts[1] != 0 else { return nil }
```

Swift's `Double(String)` accepts `"nan"`, `"inf"`, `"-inf"`, and overflow forms like `"1e999"` (→ `+inf`). The only numeric guard is `!= 0`, which **NaN and ±Inf both pass** (`Double.nan != 0` is `true`). There is also no latitude/longitude range check in either branch — the Google regex `(-?\d{1,3}\.\d+)` admits latitudes up to `999.x`.

**Attack scenario:** attacker posts/shares `https://maps.apple.com/?q=Cool%20Cafe&ll=nan,nan` (or `ll=1e999,0`, or a Google link `.../maps/place/X/@999.0,250.0`). Victim shares/pastes it into SAV-E:

1. `westernMapLinkCandidate` builds a `map_match_ready` candidate with `latitude = .nan`.
2. Persistence: `PendingPlaceImportService.appendPendingArray` (line ~603) uses `JSONEncoder()` with default `nonConformingFloatEncodingStrategy` → `EncodingError.invalidValue` → the **entire appended batch (including any legitimate candidates queued in the same write) is silently dropped** (`catch` only prints).
3. UI: if the candidate reaches a map preview before/without persistence, an `MKCoordinateRegion`/annotation built from NaN or lat>90 raises `NSInvalidArgumentException` in MapKit → crash.

Impact: targeted data-loss of queued review candidates and/or app crash from a single pasted link. No save-integrity impact (still review-gated).

**Fix:** validate both branches with `latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180` (and reject `0,0` as today). Add a regression test with `ll=nan,nan`, `ll=inf,0`, `@999.0,250.0`.

**Test gap:** `testGoogleMapsPlaceLinkBecomesMapMatchReadyCandidateWithURLCoordinates` (Tests/SocialPlacePipelineTests/SocialPlacePipelineTests.swift:2756) covers happy path only.

---

### L-1 (LOW) — Weak Google host check enables provenance spoofing of "Verified coordinates"

**File:** `SAV-E/Services/SocialLinkReviewCandidateService.swift`, `westernMapLinkMatch(in:)`:

```swift
if host.contains("google"), url.path.lowercased().contains("/maps/place/") {
```

`host.contains("google")` matches `maps.google.evil.com`, `notgoogle.cn`, etc. The same function uses the strict `matchesSocialDomain("maps.apple.com")` (exact/dot-suffix, `SocialLinkReviewCandidateService.swift:3052`) for Apple — the Google check is inconsistently loose.

**Attack scenario:** attacker circulates `https://lists.google-eats.evil.com/maps/place/Real+Restaurant+Name/@<wrong lat>,<wrong lng>`. SAV-E labels it `"Structured Google Maps place link"` + `"Verified coordinates: …"` in the evidence diagnostic, lending Google's credibility to attacker-chosen name/coordinates. Mitigations that hold: a genuine `google.com` URL can carry the same forged name/coords (the data is URL-borne either way), the candidate stays `map_match_ready` with `missingInfo: ["User confirmation required"]`, and it does **not** satisfy `canSaveAsMapStamp` (requires the literal `"google places match"` evidence string, `SocialPlaceParser.swift` diagnostic / `PendingPlaceImportService.swift:173`). So this is trust-label inflation, not a save bypass.

**Fix:** use `matchesSocialDomain("google.com") || matchesSocialDomain("google.<cc>")`-style allowlist or at minimum `host == "www.google.com" || host.matchesSocialDomain("google.com")`, and rename the evidence line to "Coordinates from link (unverified)".

---

### L-2 (LOW) — `cityOrArea(from:)` can leak full street addresses to Gemini, contradicting the documented privacy bound

**File:** `SAV-E/Services/SaveLLMClient.swift`, `SaveDrawerContextBuilder.cityOrArea(from:)`:

```swift
guard pieces.count >= 2 else { return pieces.first }
return pieces[pieces.count - 2]
```

The doc comment on `GroundedAnswerContext` claims "only place names, categories, and city/area go to the LLM — never private notes, **full addresses**, or precise coordinates." For comma-less addresses — the normal form for CJK addresses, e.g. `台北市士林區忠誠路二段200號3樓` — `pieces.first` **is the entire street-level address**, which then flows into both `digestLine(for:)` (up to ~38 chars after the 80-char line cap) and `localityHint` (no length cap on the returned key). `localityHint` additionally selects places nearest `currentLocation`, so the emitted string approximates the user's current position at street granularity.

Notes and coordinates are correctly excluded (verified: `digestLine` never touches `place.note`; `relevanceScore` uses notes only for local ranking). Caps are enforced (8 entries, 80 chars/line, 3 queries @160, answer @200) — verified by `testDrawerContextBuilderSelectsRelevantBoundedPlacesWithoutNotes` (Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift:1000), but that test only uses comma-separated US-style addresses.

**Fix:** for the `pieces.count < 2` case return `nil` (or run a CJK city-prefix extractor); add a test with a comma-less zh-TW address asserting the digest/locality contains at most the city/district.

---

### I-1 (INFO) — Evidence-bound guardrails confirmed NOT loosened (requested verification)

- `allowsDirectSave` remains `kind == .verifiedCandidate` only (`SAV-EShared/SocialPlaceParser.swift:432`); no diff touches it.
- `westernMapLinkCandidate` emits `reviewState: "map_match_ready"`, `missingInfo: ["User confirmation required"]`, and its evidence lacks `"google places match"`, so `canSaveAsMapStamp == false` and `resolverOutcome` is not `.mapStamp` (address is empty). Save requires the user's explicit "Confirm place"/"Save place" tap.
- Onboarding first clue: `OnboardingView.onComplete(trimmedClue)` → `captureOnboardingFirstClue` (`SaveApp.swift:111`) → `queueOnboardingFirstClue` (`PendingPlaceImportService.swift:522`) → `restorePendingReviewCandidates` → **review queue only**, `sourceURL` nilled, max 3 candidates. No deep-link prefill exists: `handleIncomingURL` (`SaveApp.swift:123`) routes only smoke/referral/place-share URLs and never reaches `OnboardingView`; `clueText` is user-typed `@State` (sample text is a hardcoded localized string).
- `SocialPlaceParser` `analysisSourceType` change (vs #400 a966de59 territory; changed line blames to 707dd6e3, not a #398–#401 fix): `sourceOnly → multiPlaceList` only when the source understanding already says list-shaped. `multiPlaceList` does not allow direct save and `shouldRunPublicSearch` stays evidence-gated — this is a tightening, not a regression.
- `try await recoverReviewCandidates(...)` → `try? ... ?? reviewCandidatesOrSourceOnly(...)`: swallows errors, but the fallback is the stricter deterministic local path (source-only receipts). No guard bypass; only observability of recovery failures is reduced.

### I-2 (INFO) — Untrusted-input parsing: scheme confusion / SSRF / ReDoS reviewed, no exploitable issue

- `SocialShareTextNormalizer.urlPattern` extracts only `https?://` and `iosamap|amapuri|baidumap://` — `javascript:`, `file:`, `data:` cannot be extracted from pasted text.
- Share extension fetch (`ShareViewController.shareMetadata`, line 1311) guards `url.scheme?.hasPrefix("http")`; main-app `fetchMetadata` may receive china-map schemes but `URLSession` rejects them (unsupported URL → caught → empty metadata). Fetching attacker-chosen http(s) URLs from-device is inherent to the existing link-preview feature (no privileged network position; 300 KB body cap, 2 attempts, 400 ms delay, transient-only retry — bounded). `http://` cleartext extraction is permitted (`xhslink.com` test uses it); ATS config governs actual transport.
- New regexes are backtracking-bounded (`{0,8}`, `{1,16}`, `{1,40}` classes, negated-class URL pattern is linear). No catastrophic patterns; normalizer cost is linear in paste size.
- `String(decoding: data.prefix(300_000), as: UTF8.self)` lossy decode is safe (U+FFFD substitution); previously invalid UTF-8 yielded `""`, so this strictly increases data availability without trust change.

### I-3 (INFO) — Prompt injection: present but contained (no LLM-output → action path)

Pasted captions (`sharedCaption` → `evidenceText`) and saved place names (drawer digest) reach Gemini prompts and can carry injection. Verified the blast radius: drawer grounded answers are display-text only (`replaceAgentAnswer`; `mapAction` is reset to `nil` before the request, `AIDrawerViewModel.swift:442/484`), and `GroundedAnswerJSONValidator` fail-closes on digest-only place mentions (`mentionsDisallowedResult`). Link-pipeline LLM output only shapes `PendingReviewCandidate`s, which are user-confirmed (I-1). Recent-conversation context is built solely from the local user's `chatHistory` and last response — no cross-user data source exists in this builder.

### I-4 (INFO) — Transport retry/backoff sound; pre-existing API-key-in-URL noted

`SAVEGeminiTransport`: ≤2 attempts/model × 2 models, backoff `500ms << (attempt-1)` (max 1 s), 30 s request timeout, retry only on 429/5xx/transient `URLError`. `generateContent` is stateless, so re-POST is harmless (worst case duplicate token spend). Errors carry only `upstreamStatus(Int)` — no URL/body/key in error payloads. The Gemini key remains in the URL query string (`geminiGenerateContentURL`, `SAVEProductionConfig.swift:16`) — pre-existing, unchanged in this PR; it can surface in OS-level URL caches/proxies. Consider `x-goog-api-key` header in a follow-up.

### I-5 (INFO) — Screenshot board/script: no secrets

`specs/app-store-screenshot-board.html` + `specs/export-app-store-screenshots.mjs` contain only layout/copy and local `sips`/screenshot tooling; no keys, tokens, or endpoints. UI polish diffs (MapView/PlaceCard/EmptyStateView/Color+Theme/SaveMemoryBadge) are cosmetic; new `stampMoment` state is set only after a real import.

---

## Test coverage of security-relevant behaviors

Covered: share-text normalization fixtures (douyin/xhs noise stripping, raw paste preserved), map-link priority, creator-bracket-title rejection (`allowsDirectSave` asserted false), no-hard-fail text entry (asserts **nil coordinates** for text-only clues), map-link happy path with `map_match_ready` + "User confirmation required", transport retry count, digest privacy caps + note exclusion, validator digest rejection, onboarding clue queue (no synthetic sourceURL).

Gaps: M-1 (NaN/Inf/range coords), L-1 (lookalike google host), L-2 (comma-less CJK address in digest/locality).

## Coverage limits

- Static review only; nothing was executed (no simulator run, no fuzzing of the regex set beyond inspection).
- `OnboardingView.swift` (2,367-line rewrite) and the pbxproj regen were skimmed for data-flow/secrets, not line-by-line.
- ReDoS assessment is analytical (ICU backtracking), not empirically timed against pathological pastes.
- Did not audit pre-existing paths outside the diff (e.g. `metadataValue` HTML regexes, key-in-URL) beyond confirming they were not changed.
