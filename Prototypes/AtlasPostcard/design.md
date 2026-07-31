# SAV-E Little Atlas + Postcard Pocket

Status: locked production direction
Reference: [`Reference/approved-ab-hybrid.png`](Reference/approved-ab-hybrid.png)

This file is the canonical SAV-E visual specification for Home, Saves, Trips,
Trip Plan, and Root Map. Where an older production spec conflicts with the fixed
composition, assets, type scale, or one-viewport rule below, this file wins.
Product behavior, persistence, authentication, and confirmation remain
governed by their existing contracts. Place detail uses one canonical
Postcard renderer: focused full-screen detail outside Map and a drawer on Map.

## Direction

SAV-E is a small illustrated travel keepsake that happens to be useful. It is
not a beige productivity dashboard with cute stickers.

Two page archetypes share one shell:

- **Little Atlas:** Home, Trips, Trip Plan, and Map. The map or route is the page
  skeleton. Cards float on top of geography instead of replacing it.
- **Postcard Pocket:** Saves. Review clues and confirmed Map Stamps share one
  physical ticket-and-envelope construction. State comes from the postal
  treatment: Review is sky/coral and unresolved; Map Stamps are mint/forest and
  confirmed. Selecting a Map Stamp lifts that saved postcard out of the pocket
  without introducing a second detail renderer.

First-run surfaces introduce those same archetypes instead of inventing a
third visual language. Onboarding is a short Postcard Pocket proof of
`Clue -> Review -> Map Stamp`; the opening/loading screen is Memo sorting those
same tickets into the envelope. Both use the production brand lockup, atlas
type, cream paper, coral action, mint confirmation, and owned Memo artwork.

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
Onboarding = Postcard Pocket proof
Opening    = Postcard Pocket transition
```

### Home

- Memo + SAV-E lockup, small link capsule.
- An owned illustrated city atlas fills the upper half when the resolved city
  is Tokyo, Taipei, New York, Shanghai, Beijing, Guangzhou, Shenzhen, Chengdu,
  Seoul, or the Los Angeles–Orange County region.
- All other cities use the regional live-map basic scene. Never borrow a nearby
  supported city's landmarks just because the country matches.
- Memo peeks from behind one review sheet.
- The review sheet and `Review clues` action navigate directly to Saves. Home
  never opens a review drawer; selecting a Review Candidate in Saves opens the
  focused Postcard detail and returns to the same Review queue when closed.
- Below: one Trip preview and exactly two recent Map Stamps.
- Root tabs remain visible.

### Saves

- Memo + SAV-E lockup and one capture button.
- Compact title, subtitle, and Review / Map Stamps counts.
- Review Candidate tickets are sky; Source Clue tickets are coral.
- Confirmed Map Stamp tickets reuse the exact ticket silhouette, medallion,
  title baseline, action placement, and overlapping rhythm in mint/forest.
- Every live item remains reachable by scrolling; the illustrated viewport may
  show three examples, but production must never truncate the collection.
- Tickets visibly enter one owned kraft envelope. The envelope retains its
  stitched mouth, postmark, count seal, editorial label, and contextual Memo.
- Selecting a Map Stamp presents a Lifted Saved Postcard: the selected ticket
  remains visible above cream postal paper with its photo, postmark lines,
  source receipt, memory, Add to Trip action, sharing, related sources, and
  overflow actions.
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
  changes the navigation shell to Plan / Map. Review remains owned by Saves;
  Share is the Trip header action instead of a navigation destination.
- Root tabs remain visible and the page does not scroll.

### Trip Plan

- Back, centered Trip name, Share action.
- Day selector.
- Route ribbon, numbered nodes, four compact stops with distinct imagery.
- One Add stop action.
- Plan only contains user-confirmed Map Stamps. It does not silently inject AI
  or public recommendations into the durable itinerary.
- AI discovery stays in the Map `Ask SAV-E` surface. A public suggestion must
  remain visibly unconfirmed and receive explicit approval before it can be
  added to the plan.
- Trip tabs remain visible.

### Onboarding and Opening

- Keep the existing four-step first-run proof and accessibility identifiers;
  visual unification must not change onboarding completion or clue capture.
- The header uses one Memo + SAV-E lockup, a compact step seal, and a postal
  progress rail. The page uses atlas typography rather than rounded-system
  display type.
- Language choices, clue input, Review proof, and Map Stamp proof use scalloped
  ticket construction. The selected/confirmed state is mint; coral remains the
  only primary action.
- Opening/loading is one fixed composition: brand lockup, Memo rising from the
  kraft envelope, overlapping Clue / Review / Map Stamp tickets, and one quiet
  status line. Do not restore floating scrapbook cards or a generic spinner.
- Reduced Motion keeps the final composition and removes breathing/cycling
  movement; it must not remove content or progress meaning.

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

### Canonical Postcard Detail

- Saves Review, Saves Map Stamp, Root Map place, Trip Map stop, public
  discovery, and social discovery share one Postcard renderer and chrome.
- Outside Map, it opens as a focused full-screen surface. On Root Map and Trip
  Map, it opens in the same Map drawer so closing it reveals the correct tabs.
- Global capture is a focused flow that always finishes in Saves Review. It
  never creates a Map Stamp before confirmation.
- The chrome is cream paper with a subtle perforated top rule, forest title,
  muted trust/source line, semantic seal, and outlined stamp controls.
- A saved Map Stamp uses the Lifted Saved Postcard state of that same renderer:
  a mint scalloped ticket header, Memo peeking from the pocket edge, postal
  metadata, source receipt, lined memory section, and coral Add to Trip action.
  Generic rounded dashboard cards are not an acceptable substitute.
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
- Ticket overlap is deliberate: adjacent tickets overlap by 4–8 pt and the
  envelope mouth overlaps the final ticket. Flat separated rows fail fidelity.
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
- Saves fidelity is structural, not a palette check. If the owned envelope,
  scalloped ticket silhouette, overlap, contextual Memo, and postal detail
  disappear, the implementation has left Postcard Pocket.
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
