# SAV-E Deterministic Trip Planner V2

> Last updated: 2026-08-12
> Status: implementation spec
> Builds on: `deterministic-trip-planner-v1.md` (V1 shipped through PR #113–#115)

## PM Gate

Title: Trip planner V2 — persist plans, route enhancement, opening hours

Repo: `/Users/jhinresh/projects/sav-e`

Problem: V1 produces a stable deterministic itinerary draft, but the plan is a
dead end: it cannot be saved as a Trip, stop order is straight-line
nearest-neighbor, no travel time exists between stops, and every stop carries a
permanent `.hoursUnknown` risk because opening hours are never consulted.

Goal: Close the four V1 out-of-scope items without touching backend schema:

1. **P1 — Persist AI plan as Trip.** "Save as Trip" from the itinerary canvas.
2. **P2 — Directions waypoint optimization.** Optimize per-day stop order via
   Google Routes API when available; deterministic order stays the fallback.
3. **P3 — Live travel time.** Leg durations between consecutive stops from the
   same Routes API response, rendered as in-memory decoration.
4. **P4 — Opening hours integration.** Parse structured `periods` from Place
   Details and use them to clear or escalate hours risks on planned stops.

## Acceptance criteria

### P1 Persist AI plan as Trip (independently testable slice)

- The itinerary component menu offers "Save as Trip".
- Saving distills the current canvas the same way KML export does: visible
  (non-skipped) stops whose `placeState == .confirmedMapStamp` with a valid
  saved-place UUID. External/public suggestions are never silently persisted:
  the confirmation UI states how many stops will be excluded.
- The trip is created with name (itinerary title, editable), city (from intent
  destination or first stop, editable), and all stops in one bulk persistence
  snapshot (single `updateTrip` PATCH), mapping `day`, `orderIndex`,
  `startTime = stop.time`, `duration`, `note`.
- Saving with zero eligible stops is blocked with a clear message.
- Unit tests: distillation filter, stop mapping, bulk-save round trip through
  `FakeTripPersistence`, zero-eligible rejection.

### P2 Waypoint optimization

- A new `TripRouteServiceProtocol` client calls Google Routes API
  `computeRoutes` with `optimizeWaypointOrder` for WALK/DRIVE modes only
  (TRANSIT keeps deterministic order).
- Per day: origin = first stop, destination = last stop, intermediates
  optimized. Reordered stops keep the existing category time-slot reassignment.
- Any failure (no key, network, quota, malformed response) falls back to the
  existing nearest-neighbor order — planning never blocks on the network.
- Unit tests: reorder mapping from `optimizedIntermediateWaypointIndex`,
  fallback on error/offline (URLProtocol stub), transit bypass.

### P3 Travel time

- The same `computeRoutes` response's leg durations attach to the itinerary as
  in-memory decoration (`[stopID: TravelLeg]` style), never persisted onto
  `TripStop` fields.
- The itinerary UI shows travel time between consecutive stops when available
  ("≈ 18 min walk"); nothing renders when unavailable.
- Straight-line "build in extra travel time" notes remain the fallback.
- Unit tests: leg mapping, absence when service fails.

### P4 Opening hours

- `getPlaceDetails` widens `fields` to include `opening_hours` periods and
  `utc_offset_minutes`; a structured hours model parses `periods`.
- After the deterministic draft, a best-effort annotator (bounded concurrency,
  short timeout) evaluates each planned stop's assigned time against parsed
  periods: open → clear `.hoursUnknown` risk; closed → keep risk and surface a
  `needsHoursCheck` gap with severity raised for that stop.
- Trip health is re-scored via the shared `TripHealth.scored` path.
- Annotation is decoration on the response; the deterministic draft remains
  source of truth for place IDs, day count, and stop order.
- Unit tests: periods parsing (incl. overnight spans), open/closed evaluation,
  risk clearing, annotator timeout fallback.

## Verification

- `git diff --check`
- `xcodebuild -project SAV-E.xcodeproj -scheme SAV-E -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project SAV-E.xcodeproj -scheme SAV-E -destination 'platform=iOS Simulator,id=<qa-device>' -only-testing:SAVETests CODE_SIGNING_ALLOWED=NO test`

## Constraints

- **Do not touch backend schema or backend/src.** `trip_stops` field allowlist
  is strict; travel time and hours are never persisted on stops.
- Routes API uses the existing key chain
  (`GOOGLE_DIRECTIONS_API_KEY ?? GOOGLE_PLACES_API_KEY ?? Secrets.plist`); if
  the Google Cloud project has not enabled Routes API, every path degrades to
  V1 behavior. Enabling the API is a human/console action, not code.
- LLM polish must not gain authority: validators keep re-deriving state/risks
  from the deterministic draft.
- `Place` model changes must use defaulted fields (≈15 test fixture files
  construct it).

## Out of scope

- Booking, reservations, flights, payments.
- Multi-day re-clustering by drive time (day grouping stays distance-based).
- Persisting travel time or structured hours to Supabase.
- Transit waypoint optimization.
- Backend changes of any kind.

## Do not touch

- TestFlight build numbers, signing settings.
- Social import parser behavior.
- backend/ directory.
