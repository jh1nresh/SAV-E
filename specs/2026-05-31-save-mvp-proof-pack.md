# SAV-E MVP Proof Pack

> Last updated: 2026-05-31

## Product Claim

SAV-E is a cute place-memory scout, not a generic AI travel planner or map app.

Core loop:

```text
messy place signal
-> Source Clue / Review Candidate
-> confirmed Map Stamp
-> ask saved places first
```

## Target User

People who already save restaurants, cafes, attractions, and trip ideas across
Instagram, TikTok, Xiaohongshu, Google Maps, screenshots, and friend messages,
then cannot find or trust those places when making a decision.

Primary decision moments:

- nearby coffee or dinner;
- date night;
- group meal;
- trip planning from saved spots;
- remembering a friend-recommended place.

## Pain Proof

Observed user pain:

```text
I saw many places I wanted to try.
Friends sent me places.
Google Maps, IG, TikTok, and Xiaohongshu all have saved places.
When it is time to choose, I still search again.
```

Market validation:

- Roamy validates the saved-social-spots wedge: social saves -> map -> trip.
- Mapstr validates personal place organization.
- Google/Apple Maps validate map utility but not provenance or decision memory.

SAV-E differentiation:

- review before save;
- no fake confirmed pins;
- source evidence remains visible;
- public discovery is clearly separate from `From your SAV-E`.

## MVP Boundary

In:

- social URL/text/image/screenshot capture;
- Source Clue / Review Candidate / Map Stamp states;
- confirm-before-save trust layer;
- Ask from saved places first;
- nearby restaurant / cafe recommendation with grounded Gemini narration.

Out:

- generic save-anything vault;
- generic AI travel agent;
- booking, payment, or POS actions;
- hard paywall before first useful place-memory artifact;
- Roamy-style action extension as a blocker.

## First Distribution Video Hook

Short-form before/after:

```text
I had 200 saved restaurants and still searched "best dinner near me."
SAV-E turns messy Reels and map links into a private place memory,
then answers from places I already wanted to try.
```

Storyboard:

1. Show messy Reel / friend link / screenshot.
2. Share or paste into SAV-E.
3. SAV-E creates a Review Candidate, not a fake saved pin.
4. Confirm into Map Stamp.
5. Ask: `recommend nearby coffee` or `date night from my saved places`.

## Paywall Hypothesis

Do not hard-paywall first launch.

Hypothesis:

```text
free: first captures, Review Candidate, a small number of Map Stamps
pro: high-volume imports, advanced OCR/social recovery, saved-memory chat,
     trip planning, and larger private place graph
```

Candidate pricing:

- monthly: $7.99-$9.99;
- yearly: $39.99-$49.99;
- trial only after the user sees one useful Review Candidate or Map Stamp.

## Readiness Call

Current status:

```text
internal dogfood MVP: yes
trusted TestFlight MVP: after real-device smoke
public revenue MVP: not yet
```

Public revenue MVP still needs:

- real-device smoke: auth, location, nearby restaurant/coffee, share IG/Maps,
  review confirm/save;
- first distribution video draft;
- App Store screenshots using cute scout + place memory + review-before-save;
- explicit paywall copy after first value proof.
