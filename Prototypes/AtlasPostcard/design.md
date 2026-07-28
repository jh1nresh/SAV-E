# SAV-E Little Atlas + Postcard Pocket

Status: locked prototype direction
Reference: [`Reference/approved-ab-hybrid.png`](Reference/approved-ab-hybrid.png)

## Direction

SAV-E is a small illustrated travel keepsake that happens to be useful. It is
not a beige productivity dashboard with cute stickers.

Two page archetypes share one shell:

- **Little Atlas:** Home, Trip Plan, and Map. The map or route is the page
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
Trip Plan = Little Atlas
Root Map  = Little Atlas
```

### Home

- Memo + SAV-E lockup, small link capsule.
- Illustrated Tokyo atlas fills the upper half.
- Memo peeks from behind one review sheet.
- Below: one Trip preview and exactly two recent Map Stamps.
- Root tabs remain visible.

### Saves

- Memo + SAV-E lockup and one capture button.
- Compact title, subtitle, and three counts.
- Two blue Review Candidate tickets and one coral Source Clue ticket.
- Tickets visibly enter one kraft envelope with a review-count seal.
- Root tabs remain visible; no generic card list replaces the pocket.

### Trip Plan

- Back, centered Trip name, Memo.
- Day selector.
- Route ribbon, numbered nodes, four compact stops with distinct imagery.
- One Add stop action.
- Trip tabs remain visible.

### Root Map

- Illustrated atlas fills the viewport.
- Pins and dashed route are part of the atlas composition.
- One compact place card sits above the fixed Root tabs.
- No modal sheet and no second drawer in this prototype.

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

- System rounded type, three weights maximum.
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
