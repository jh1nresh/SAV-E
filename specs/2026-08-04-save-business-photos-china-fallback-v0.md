# Business Photos: China Fallback v0

> Status: SPEC — diagnosed 2026-08-04; slice A implementable now, slice B blocked on Amap key
> Owner: JhiNResH

## Problem

Place detail can show no business photos. Root cause confirmed in code:
`PlaceBusinessEnricher` fetches photos **only** from Google Places
(photo_reference → `/maps/api/place/photo`). For places in mainland
China, Google has no/poor coverage, so `businessPhotoUrls` stays empty.
Amap today is a coordinate/refine provider only (`ChinaMapDeepLinkParser`
parses share links client-side); there is **no Amap API integration and
no Amap key anywhere** (checked `.env.example` and backend config).

## Slice A — graceful fallback (no new keys)

- When `businessPhotoUrls` is empty, the detail surface falls back to the
  clue's `sourceImageUrl` (social post image) instead of an empty gallery.
- Hide the photos section entirely when neither exists — no empty frame.
- Done when: a China place detail shows the source image or no gallery,
  never a blank photo area.

## Slice B — Amap photo enrichment (needs founder credential)

- Founder registers an Amap Web API key（高德開放平台）— server-side only,
  Railway env, never shipped in the app.
- Backend endpoint proxies Amap place detail (`/v3/place/detail`) and
  returns photo URLs; enricher routes by provenance/region: place with
  amap/baidu/dianping provenance or GCJ-02 coordinates in China → Amap
  first, else Google. Existing values win (same merge rule as today).
- Done when: a Dianping/Amap-sourced Map Stamp shows Amap photos in
  detail with the key configured; non-China places unchanged.

## Out of scope

Baidu photo API, photo caching policy changes, review-candidate photos.

## Verification

- Slice A: simulator screenshot of a China place detail — no blank gallery.
- Slice B: backend unit test for the proxy + simulator screenshot with a
  staging key.
