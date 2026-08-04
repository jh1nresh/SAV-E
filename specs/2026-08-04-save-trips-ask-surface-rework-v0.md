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
expands the ask surface **in place** — the on-screen panel grows into the
conversation view. No tab switch, and no second drawer stacked on top of an
existing one (founder decision 2026-08-04: the visible surface itself
expands; never present an additional drawer over it).

Acceptance scenarios:

- Given Trips is open, when the user taps the ask field, then the keyboard
  appears and typed text renders in the field — still on Trips.
- Given a typed question, when the user submits, then the on-screen panel
  expands into the ask conversation and the answer references confirmed Map
  Stamps. No new drawer/sheet layer is presented.
- Given the expanded panel is collapsed, then the user is still on Trips
  with prior scroll state.
- Existing `trips.assistant` accessibility id stays on the ask entry so
  current UI tests keep passing.

## P2 — Drawer visual + presentation convergence

Ask/search drawer adopts Atlas surfaces: paper background, kraft chip
treatment, editorial type, postage accents. Presentation rule applies on
Map too: tapping the resting shelf expands that same shelf in place —
today it presents a second drawer on top of the resting one (reported
2026-08-04). One surface, two states (resting / expanded); never two
stacked drawers. Judged by side-by-side crop against `DESIGN.md` Atlas
tokens.

## P2b — One place, one card (Map selection)

Selecting a saved place on Map currently shows the Atlas place card and,
beneath it, the legacy `SavePlaceDrawerPresentation` strip ("Map Stamp ·
From your SAV-E" with share/close) at the same time (reported 2026-08-04).
Same rule as P2: one surface per object. The Atlas card is canonical; the
legacy strip must not co-present. Fold its actions (share, plan-around,
note) into the card.

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
