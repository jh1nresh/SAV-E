# Share Extension Social Review Only

> Last updated: 2026-05-22

## Problem

Social posts can expose partial public metadata: caption fragments, creator
profiles, handles, thumbnail text, or address-like strings. The Share Extension
previously allowed social metadata with a parsed address to geocode directly
into a Map Stamp preview. That can look product-ready but is too risky for
Instagram, TikTok, Xiaohongshu, and similar links because public metadata is not
a verified place record.

## Goal

For social URLs, SAV-E should behave like an agent: collect evidence, produce
review candidates, and ask the user to confirm before a place can become a saved
Map Stamp.

## Product Contract

```text
social URL
-> fetch public metadata and optional thumbnail OCR
-> shared SocialPlaceParser evidence analysis
-> pending review candidates, if evidence is strong enough
-> source-only capture/error if evidence is insufficient
-> main app review/refine/save flow
```

## Acceptance Criteria

- Share Extension social URLs do not call the deterministic metadata geocode path.
- Share Extension social URLs do not become `parsedPlace` / "Ready to save Map Stamp" directly.
- Social URL candidates are written to pending review candidate storage.
- If no reliable candidate is found, the source is preserved as source-only memory and the UI asks for a map link, screenshot, or clearer caption.
- Map URLs with explicit coordinates still use the existing deterministic Map Stamp path.
- Gemini fallback remains available for non-social content only.
- iOS app build and Share Extension build pass.

## Out of Scope

- Platform-authenticated scraping.
- Downloading full videos or extracting multiple video frames.
- Backend schema changes.
- TestFlight build bump.
