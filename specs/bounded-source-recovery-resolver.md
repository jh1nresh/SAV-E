# Bounded Source Recovery Resolver

Status: implemented v1
Date: 2026-05-25

## Goal

SAV-E should not rely on a model directly guessing places from social links.
The social import pipeline must first produce a bounded resolver decision from
the evidence it actually has.

## Problem

The app can parse captions, OCR text, handles, map links, booking links, and
public-search hints, but those signals need one shared decision layer before the
UI or persistence layer decides what to do next. Without that contract, weak
evidence can look like a real place, source-only links can look like failed
analysis, and multi-place lists can collapse into one bad candidate.

## Scope

- Add a `SocialPlaceResolverDecision` contract to the shared parser.
- Support five decisions:
  - `verifiedCandidate`
  - `pendingCandidate`
  - `multiPlaceList`
  - `sourceOnly`
  - `reject`
- Expose guardrail fields:
  - `allowsDirectSave`
  - `shouldRunPublicSearch`
  - `requiredEvidence`
  - `nextAction`
  - `reviewState`
- Keep the first implementation deterministic.
- Add regression tests for:
  - place-bearing recommendation without venue
  - multi-place handle list
  - vague lifestyle caption
  - map share
  - booking source
  - creator-only source

## Non-goals

- No logged-in Instagram/TikTok scraping.
- No automatic video download.
- No direct save from weak public evidence.
- No model/provider swap.
- No backend schema change.

## Future GPT Resolver Boundary

A future GPT resolver may replace only the final ranking/decision step:

```text
evidence atoms + public search results + map/booking hints
-> choose resolver decision
-> produce reason/confidence/missing evidence
```

It must not invent addresses or coordinates. It must return JSON matching this
contract and keep weak evidence in Review.

## Acceptance

- A source with no place-bearing evidence becomes `sourceOnly` or `reject`.
- A vague lifestyle caption is rejected instead of becoming a place candidate.
- A map or booking source becomes `pendingCandidate` until structured place
  resolution confirms it.
- A multi-place list stays `multiPlaceList`.
- A place-bearing Reel with no venue name stays `pendingCandidate` and may run
  public search recovery.
- `allowsDirectSave` remains false unless coordinates/map evidence are verified.
