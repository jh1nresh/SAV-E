# Instagram video venue fallback

After ordinary capture recovery produces no venue, `SAVE_ENABLE_VIDEO_VENUE_ANALYSIS=true` enables a bounded visual fallback. It uses public Instagram video content, samples up to eight frames throughout a short clip, and asks the existing Gemini 2.5 Flash model for explicit venue text and frame seconds. It does not transcribe or upload audio. Results remain review candidates and follow the existing Places/rubric/user-confirmation route.

Deployment must include `nixpacks.toml` and the pinned `requirements-video.txt`. The runtime needs yt-dlp, ffmpeg, ffprobe and the existing GEMINI_API_KEY (or GOOGLE_GEMINI_API_KEY). `/health/source-recovery` checks required tools when enabled. No cookies, accounts, public multimodal proxy or provider tools are enabled. Setting the flag false disables the fallback without a migration. Enabling or deploying production remains a separate authorized action.

Limits: public Instagram post URLs only, 24MB download, 90-second clip, eight bounded JPEG frames, one model request with bounded output and timeout. Usage reservations and token settlement use the existing analysis session; quota denial stops the flow. Unsupported/private/deleted videos, no readable venue text, or provider failures preserve the original clue; provider failures remain diagnostic. Temporary video and frames are removed after each attempt. Successful capture recovery is reused by the existing ownership-scoped recovery cache; the video pipeline version participates in its key.

The real regression source is Reel DcTZXFrjfJG: its caption and thumbnail do not name the store, but the storefront near 24s reads 江牛樓. The committed tests use redacted metadata, mocked model output and boundary fixtures. The local public-video proof is not a live production Gemini quality benchmark. Production readiness still requires an authenticated end-to-end test under the real usage ledger.

Share and other canonicalization routes such as `/share/reel/...` are not gated paths for yt-dlp. Source resolution must supply the resolved `/reel|reels|p/<id>/` URL to the video fallback; evidence and media evidence on that path use the same resolved URL.

## Feature brief

### Paid user job / observed failure

A paid (or would-pay) user saves a public Instagram Reel whose caption and cover do not name the venue. Ordinary recovery stays `source_only_clue`. The visible storefront (fixture: 江牛樓 near 24s on Reel DcTZXFrjfJG) is readable in the public video. Share links that resolve to a `/reel/<id>/` URL currently never reach that fallback if the original `/share/reel/...` URL is passed through.

### Acceptance criteria and failure fixture

- Flag default remains off. `SAVE_ENABLE_VIDEO_VENUE_ANALYSIS` is not true unless a human enables it. Merge does not activate the fallback.
- After metadata, media, and public-search drafts are empty, the fallback may run once on a public Instagram post URL.
- Share/canonical stored URLs invoke the fallback with the resolved gated path (`/reel|reels|p/<id>/`), not `/share/reel/...`. Evidence and `video_keyframe` URLs use that resolved URL.
- Recovered names stay unconfirmed review candidates; Places/rubric/user confirmation still apply. Failures and quota denial preserve the original clue.
- Failure fixture: share URL `https://www.instagram.com/share/reel/ShareCode/` persisted as resolved `https://www.instagram.com/reel/DcTZXFrjfJG/` must call video recovery with the reel URL. Direct share URLs remain unsupported at the yt-dlp gate.

### Classification

Feature. Opt-in backend recovery loop on the existing capture search-recovery path. Not a new product surface, tab, or commerce flow.

### Demand proof, pricing/paywall hypothesis, first distribution format

- Demand proof (hypothesis): founder-observed Reel DcTZXFrjfJG stays source-only after caption/public-search recovery; users who save Instagram food videos hit this gap first.
- Pricing/paywall hypothesis: the fallback consumes the existing metered analysis session (metadata + one Gemini 2.5 Flash reserve). No new StoreKit product, credit pack, or paywall in this PR. Quota denial stops the flow; users should not be charged a separate video SKU.
- First distribution format: this PR against `main` as an off-by-default backend capability. No Railway/prod enablement, TestFlight, or App Store Connect from this packet.

### Files and systems in scope

- `backend/src/videoVenueAnalysis.ts` and `backend/src/videoVenueAnalysis.test.ts` — gated public-video frame recovery
- `backend/src/sourceSearchWorker.ts` and `backend/src/sourceSearchWorker.test.ts` — fallback after empty drafts; resolved URL for yt-dlp and evidence
- `backend/src/sourceRecoveryConfig.ts` and `backend/src/sourceRecoveryConfig.test.ts` — `/health/source-recovery` readiness when enabled
- `backend/src/server.ts` — recovery cache key includes `frames-v1` only when the flag is true
- `backend/nixpacks.toml`, `backend/requirements-video.txt` — pinned yt-dlp plus ffmpeg/ffprobe
- `SAV-E/Services/SupabaseService.swift` — 180s timeout for capture search-recovery
- `backend/VIDEO-ANALYSIS.md` — this brief

Out of scope: PR #243, Friends/Passport revocation, activating the flag, Railway/Vercel/prod, App Store Connect, TestFlight, audio/ASR, cookies, or a public multimodal proxy.

### Verification

```bash
cd backend
npm test
# focused share→resolved + video gate, after build:
node --test \
  dist/sourceSearchWorker.test.js \
  dist/videoVenueAnalysis.test.js \
  dist/sourceRecoveryConfig.test.js
git diff --check
```

Flag-off default: `readSourceRecoveryConfigStatus({})` reports `videoVenueAnalysis.enabled === false`. Do not set `SAVE_ENABLE_VIDEO_VENUE_ANALYSIS=true` in CI or production from this PR.

### Security and privacy

Anonymous public Instagram post URLs only. No cookies, credentials, or account login. Downloads are byte- and duration-bounded; temp files are removed. Model input is JPEG frames plus a fixed prompt; audio is not uploaded. Results are owner-scoped review candidates, not Map Stamps. Provider errors stay diagnostic and must not leak keys, paths, or upstream details.

### Actions that still require human approval

Merge, production secrets/schema, Railway or Vercel deployment, setting `SAVE_ENABLE_VIDEO_VENUE_ANALYSIS=true`, signing, App Store Connect, and TestFlight.
