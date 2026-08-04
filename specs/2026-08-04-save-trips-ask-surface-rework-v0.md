# Trips / Ask Surface Rework v0

> Status: SPEC — approved direction, not yet implemented
> Owner: JhiNResH · Drafted: 2026-08-04
> Evidence: 2026-08-03 simulator QA session (SAV-E-Envelope-QA, 402×874)

## Problem

Five symptoms reported in one QA pass share one root: the Trips and ask
surfaces are still prototype-era.

1. Trips reads as cluttered: fixed `402×786` canvas + `.placed()` absolute
   coordinates ([ContentView.swift] trips case, `Screens.swift` TripsScreen),
   oversized empty "Next journeys" panel.
2. The Trips ask entry is a Button styled as a text input
   (`Screens.swift:758`, `trips.assistant`) — users try to type and nothing
   accepts input.
3. Tapping it silently switches tab to Map and opens the AI drawer there —
   jarring, and the user loses Trips context.
4. The AI drawer's visual language (flat white panels, yellow FILTERS/TRY
   ASKING chips) diverges from the Atlas paper/kraft/postage system used
   everywhere else.
5. Location: the locate button was buried under the drawer (fixed in PR #71);
   a denied permission still fails silently with no recovery affordance.

## Product boundary

- SAV-E is private place memory; ask/planning draws from confirmed Map
  Stamps first. No new backend, parser, or persistence work in this rework.
- TREK planning adapter stays in PR #61 — this spec must not touch it, but
  the P1 ask entry must not preclude routing to it later.

## P1 — Ask in place on Trips (independently testable)

Replace the fake-input Button with a real inline ask field on Trips. Submit
runs the existing `AIDrawerViewModel` ask flow presented as a sheet **over
Trips** — no tab switch.

Acceptance scenarios:

- Given Trips is open, when the user taps the ask field, then the keyboard
  appears and typed text renders in the field — still on Trips.
- Given a typed question, when the user submits, then the ask flow presents
  as a sheet over Trips and the answer references confirmed Map Stamps.
- Given the sheet is dismissed, then the user is still on Trips with prior
  scroll state.
- Existing `trips.assistant` accessibility id stays on the ask entry so
  current UI tests keep passing.

## P2 — Drawer visual convergence

Ask/search drawer adopts Atlas surfaces: paper background, kraft chip
treatment, editorial type, postage accents. No behavior change. Judged by
side-by-side crop against `DESIGN.md` Atlas tokens.

## P3 — Trips layout de-clutter

Replace the fixed-canvas Trips screen with flow layout honoring
`AtlasMetrics.statusBarHeight`; collapse the empty "Next journeys" panel to
a one-line hint; keep trip tickets and CTA above the tab bar.

## P4 — Location denied recovery

When locate is tapped with permission denied/restricted, show an Atlas-style
notice with an Open Settings action instead of a silent no-op.

## Out of scope

TREK adapter (PR #61), onboarding, Saves, backend/API, pricing, sharing.

## Verification

- Per-slice: focused UI test + full-screen screenshot on 402×874 compared
  against the Atlas reference crops.
- `SAVEUITests` suite stays green; no regression in `SAVE-First-Run` CI
  screenshots.
- P1 ships alone first; P2–P4 each land as separate reviewable PRs.
