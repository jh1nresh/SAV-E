# SAV-E Trips Chat + Map Shelf — Production Decision

Status: selected by founder on 2026-07-29

## Thesis

SAV-E remains a Little Atlas of confirmed memories. Trips accepts
conversational planning intent without becoming a chat app; Map supports
browsing without becoming the product home.

## Selected Screen Rules

- Root navigation remains Home / Saves / Trips / Map.
- Trips keeps its featured Trip and journey tickets. A cream planning chatbar
  replaces the oversized New Trip CTA; a compact coral plus keeps New Trip
  directly reachable.
- The chatbar opens the existing SAV-E assistant at medium height and focuses
  its command field. It does not create a second chat store.
- Root Map keeps live MapKit and shows one bottom paper shelf only:
  - default: search/ask prompt plus confirmed Map Stamp count;
  - selected: place peek plus close and Open details;
  - full detail: the existing canonical place-detail surface.
- No arbitrary first place is selected by default. No top and bottom search bars
  appear together. No permanent Map drawer appears on Home, Saves, or Trips.

## Visual Contract

- Preserve `AtlasPalette`, `AtlasType`, Memo, owned landmark assets, fixed root
  tabs, paper opacity, and the 402 x 874 no-scroll viewport.
- Coral is the only primary action color; mint remains confirmed/selected.
- Map landmarks and Memo are optional owned overlays; geographic truth always
  comes from MapKit.
- Minimum target is 44 pt and all controls have explicit accessibility labels
  and identifiers.

## Product and Scope Boundary

The durable flow remains Clue -> Review -> confirmed Map Stamp -> Trip -> Day
Plan. This slice adds no booking, navigation, new backend, chat persistence,
route optimization, public guide, or new location permission.

## Verification

- Generic iOS Simulator build.
- Trips screenshot: chatbar, New Trip, existing cards, fixed tabs.
- Root Map default screenshot: one search shelf, no place card.
- Root Map selected screenshot: one place peek, fixed tabs, explicit close.
- Focused runtime confirms assistant presentation and return to the root tabs.
