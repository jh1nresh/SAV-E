# SAV-E Little Atlas + Postcard Pocket

Status: locked production direction
Reference: [`Reference/approved-ab-hybrid.png`](Reference/approved-ab-hybrid.png)

This file is the canonical SAV-E visual specification for Home, Saves, Trips,
Trip Plan, and Root Map. Where an older production spec conflicts with the fixed
composition, assets, type scale, or one-viewport rule below, this file wins.
Product behavior, persistence, authentication, confirmation, and the single
canonical place-detail drawer remain governed by their existing contracts.

## Direction

SAV-E is a small illustrated travel keepsake that happens to be useful. It is
not a beige productivity dashboard with cute stickers.

Two page archetypes share one shell:

- **Little Atlas:** Home, Trips, Trip Plan, and Map. The map or route is the page
  skeleton. Cards float on top of geography instead of replacing it.
- **Postcard Pocket:** Saves. Unresolved clues are physical ticket/postcard
  objects inserted into one kraft envelope. Confirmed Map Stamps are counted,
  but they are not styled as unresolved mail.

## Design-taste brief

- **Direction:** playful illustrated field atlas + collectible postcard pocket
- **Density:** comfortable; one viewport tells one story
- **Surface:** continuous atlas on Home/Plan/Map; one physical envelope on Saves
- **Type mood:** friendly, editorial, compact
- **Motion:** gentle spring in, quick fade out
- **Do:** let geography lead, make paper construction legible, use Memo as a
  guide, keep one shared tab shell, reserve coral for the main action
- **Don't:** build a pastel card dashboard, nest glass cards, repeat one radius,
  inflate typography, or treat a stock MapKit crop as an illustrated atlas

## Locked composition

```text
Home      = Little Atlas
Saves     = Postcard Pocket
Trips     = Little Atlas
Trip Plan = Little Atlas
Root Map  = Little Atlas
```

### Home

- Memo + SAV-E lockup, small link capsule.
- An owned illustrated city atlas fills the upper half when the resolved city
  is Tokyo, Taipei, New York, Shanghai, Seoul, or the Los Angeles–Orange County
  region.
- All other cities use the regional live-map basic scene. Never borrow a nearby
  supported city's landmarks just because the country matches.
- Memo peeks from behind one review sheet.
- Below: one Trip preview and exactly two recent Map Stamps.
- Root tabs remain visible.

### Saves

- Memo + SAV-E lockup and one capture button.
- Compact title, subtitle, and three counts.
- Two blue Review Candidate tickets and one coral Source Clue ticket.
- Tickets visibly enter one kraft envelope with a review-count seal.
- Root tabs remain visible; no generic card list replaces the pocket.

### Trips

- Memo + SAV-E lockup, compact title, and the one global link entry.
- A cropped atlas is the background for one featured current or next Trip
  postcard; it is not a generic dashboard hero.
- At most two upcoming or planning Trip tickets are visible in the fixed
  viewport.
- One cream planning chatbar opens the existing SAV-E assistant with focus.
  Chat is an input surface only; Trip cards and Day Plan remain the durable
  output.
- One adjacent coral New Trip action remains directly reachable. Opening a Trip
  changes the navigation shell to Plan / Map / Inbox / Share.
- Root tabs remain visible and the page does not scroll.

### Trip Plan

- Back, centered Trip name, Memo.
- Day selector.
- Route ribbon, numbered nodes, four compact stops with distinct imagery.
- One Add stop action.
- Trip tabs remain visible.

### Root Map

- Live MapKit fills the viewport below the SAV-E header. Owned landmark, Memo,
  pin, and route accents may sit above it without obscuring geographic truth.
- One cream Map command shelf sits above the fixed Root tabs. Its default state
  contains a grabber, `Search places or ask SAV-E`, and the confirmed Map Stamp
  count.
- Selecting a pin changes that same shelf into a compact place peek. Closing it
  returns to search; `Open details` transitions to the single canonical
  place-detail surface.
- The persistent Map shelf exists only on Root Map and Trip Map. Home and Saves
  may still present task-specific capture/review sheets, but never a permanent
  Map drawer.
- Never show a top search bar and bottom search drawer together, a default
  arbitrary first-place card, or two place renderers at the same time.

### Canonical Postcard Drawer

- Home capture, Home review, Saves review, Saves Map Stamp, Root Map place,
  Trip Map stop, public discovery, and social discovery share one drawer
  chrome.
- The chrome is cream paper with a subtle perforated top rule, forest title,
  muted trust/source line, semantic seal, and outlined stamp controls.
- Collapsed, medium, and large detents keep the same paper identity.
- Existing data and actions remain live SwiftUI. The visual unification never
  creates a second place-detail renderer or changes confirmation semantics.

## Tokens

```text
canvas      #FFF8EE
paper       #FFFDF7
forest      #174E37
ink         #3F281A
muted       #80664F
coral       #F27D5C
mint        #D9EACB
sky         #CDEDF4
lavender    #E8DEF7
kraft       #EFD0A5
route ink   #4D4339
```

Coral is the only action accent. Mint, sky, and lavender may describe state or
geography, never competing primary actions.

## Shape and type

- Avenir Next Condensed is the prototype display and body family, with three
  weights maximum. The approved raster is the baseline; do not substitute
  SF Rounded or guess a different editorial font per page.
- Screen title 28 pt maximum; place title 16–18 pt.
- Tickets have a dashed/perforated edge; ordinary rows do not.
- Envelope uses a different silhouette from cards.
- Tab active state is one pale mint lozenge.
- Shadows stay under 8% opacity.

## Anti-slop gate

Reject the prototype if three or more are true:

- every section is a rounded card;
- all components share the same radius and padding;
- more than one bright action color competes on a page;
- the map is only a rectangular screenshot behind a dashboard;
- the paper metaphor could be removed without changing the Saves silhouette;
- Home, Saves, Plan, and Map could belong to four different apps;
- primary content requires scrolling in the 402 × 874 pt review viewport.

## Fidelity implementation contract

- All five pages render in one fixed 402 × 874 reference viewport. The top
  48 pt is system-owned; app content uses the measured anchors in
  `Reference/layout-metrics.json`.
- Keep the existing root/trip navigation state, but do not use `ScrollView`,
  `safeAreaInset`, or flexible spacers to place primary sections.
- Approved illustrations come from the local, section-level assets declared in
  `Reference/asset-manifest.json`. A whole-screen screenshot background is
  forbidden.
- Live SwiftUI remains responsible for titles, counts, ticket actions, stop
  rows, place details, and both tab shells.
- Every review run exports `reference/`, `output/`, `diff/`, and `results/`.
  `Scripts/VisualParity.swift` ignores only the system-owned top 48 rows and
  combines tolerant edge overlap (35%) with per-pixel appearance similarity
  (65%). The four raster-approved pages must score at least 0.90. Trips uses
  the same production component and structural UI gate until its own approved
  raster is locked.

## Live map exception

The approved Map raster establishes composition, palette, card geometry, and
navigation—not permission to replace the product map with a static image.
Production Root Map and Trip Map keep MapKit, location, saved pins, numbered
stops, selection, and route interaction. Use a flat muted MapKit style under
the approved header and single command-shelf geometry. The illustrated fixture
remains a visual-direction comparison; a separate UI test must exercise the
live MapKit component tree, both shelf states, and return from place detail to
the correct fixed tabs.
