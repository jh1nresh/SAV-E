# SAV-E Deterministic Trip Planner V1

> Last updated: 2026-05-24
> Status: implementation spec

## PM Gate

Title: Add deterministic trip planner before Gemini polish

Repo: `/Users/jhinresh/projects/wanderly-current`

Problem: SAV-E itinerary planning currently depends on Gemini to choose places, order stops, and invent a schedule from raw saved-place metadata. That makes plans feel intelligent when Gemini behaves, but unstable when saved places span multiple cities, when Gemini overgeneralizes, or when the API key/rate limit fails.

Goal: Add a deterministic planner layer that produces a stable itinerary draft from saved places before Gemini polish.

Acceptance criteria:

- Itinerary-like queries use deterministic planning first.
- The deterministic planner filters likely destination/category matches from saved places without assuming a default city.
- It groups selected places into days and orders each day by nearest-neighbor distance.
- It assigns simple time slots using category rules: breakfast/cafe, lunch/food, attraction/shopping/stay, dinner/food/bar.
- Gemini, when available, receives the deterministic draft and is instructed to polish explanation/notes without inventing place IDs.
- If Gemini is missing or fails, SAV-E still returns the deterministic itinerary draft.
- Unit tests cover day grouping, geographic ordering, and meal/time slot assignment.

Verification:

- `git diff --check`
- `xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project Wanderly.xcodeproj -scheme Wanderly -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -configuration Debug test`

Out of scope:

- Google Directions waypoint optimization.
- Live travel time estimation.
- Google Places opening-hours integration.
- Persisting AI-generated plans as trips.
- Booking, reservations, flights, payments, or external agent calls.

Do not touch:

- TestFlight build numbers.
- Signing settings.
- Backend schema.
- Social import parser behavior.

## Planning Contract

Pipeline:

```text
saved places
-> query intent/destination filter
-> distance clustering / nearest-neighbor ordering
-> day grouping
-> meal/time slot assignment
-> deterministic itinerary draft
-> Gemini polish explanation when available
```

The deterministic draft is the source of truth for:

- place IDs;
- day count;
- stop order;
- first-pass times;
- map route place IDs.

Gemini may polish:

- title;
- `aiMessage`;
- stop notes.

Gemini must not:

- introduce unknown place IDs;
- claim live travel time;
- assume a city that is not in saved places or the user query.

## Rule Details

Destination/category filtering:

- Prefer saved places whose `name`, `address`, or `category` matches query tokens.
- Preserve all places when the query does not contain destination/category clues.
- If filtering leaves too few places, fall back to all saved places so SAV-E still produces a useful draft.

Day grouping:

- Requested day count comes from text like `2 day`, `2-day`, `3 days`, `2天`, or `2日`.
- If no day count is present, choose a practical count from selected place count.
- Cap stops per day to a small mobile-friendly itinerary.

Ordering:

- Sort selected places into a nearest-neighbor route using latitude/longitude.
- Start each draft from the westernmost/northernmost selected place for deterministic repeatability.

Time slots:

- Cafe first in the morning when available.
- Food places fill lunch/dinner.
- Bar places prefer evening.
- Attractions/shopping/stays fill mid-day.
- Notes should say when stops are far apart instead of pretending travel is easy.

## Future Work

- Replace straight-line distance with Google Directions travel time.
- Add Google Places opening-hours constraints.
- Add preference scoring from R-8/user memory.
- Save accepted plans into persistent trips.
