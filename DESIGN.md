# Savvy Design System

> Last updated: 2026-10-21
> Status: source of truth for native iOS design work
> Token systems: **Atlas Postcard** still governs paper, type, kraft, and coral
> chrome, with the 2026-10-19 v5 cream/ink/stroke lock below. **Tile-town**
> remains the product Map base until the Doodle Map PR
> (founder lock 2026-10-14). Home and Friends no longer use it. Founder 2026-10-20:
> 「像素小鎮已經不要了」 — tile-town is abandoned; this stack keeps only
> shared leftovers for a later cleanup. The 2026-10-19 isometric Home hero
> is withdrawn. **Soft Pixel** is accents-only on remaining town surfaces
> (pins / seals / Memo). **Cream-notebook** tokens are legacy-surface-only.
> See "Tile Town", "Atlas Postcard Tokens", and "Legacy Cream-Notebook
> Tokens" below.

## Product Frame

Savvy is a personal place-memory agent. Users send messy place signals: links, posts,
screenshots, notes, maps, imports. Savvy preserves the source, identifies the real
place when it can, asks before saving uncertain matches, and turns confirmed places
into a map-ready memory.

The app is not a generic travel bookmark manager. It is the user's field notebook
for place memory, evidence, and review.

Assumptions locked by current code:

- Native app is SwiftUI. Product Home is `SaveDoodleHomeView`: a nearby
  Eat/Go list plus a native MapKit mini-map. Product Map still uses
  `SaveTileTownCanvas` until the Doodle Map PR. MapKit also remains for Trip
  maps and Apple Maps handoff.
- `Color+Theme.swift` owns the current palette tokens, including
  `SaveTileTownPalette`.
- `MemoMascotMark` owns the Memo elephant mark.
- `SaveKraftStamp` is the one stamp language for Home recent stamps and the
  Passport grid. `SaveMemoryBadge`, `PlaceMapPin`, and `ReviewCandidateMapPin`
  still split clues, review candidates, and Map Stamps.
- `ProfileView` is the Savvy Passport, not a generic settings page.

## Design Thesis

Savvy should feel like a cream field notebook that happens to have a map inside it.

The interface language is:

```text
Memo elephant -> cream notebook -> source clue -> review candidate -> map stamp -> passport
```

Every screen should make one of those states obvious. If a user cannot tell whether
an item is a clue, a candidate, or a saved place in five seconds, the UI failed.

## Platform Boundary

Borrow Apple Maps for spatial navigation. Own Savvy semantics for memory, source
evidence, saved state, review candidates, lists, and AI actions.

Apple Maps is the reference for map literacy, not the product identity. Savvy can
reuse platform-native patterns such as map gestures, current-location placement,
bottom drawer mechanics, selected-place focus, and compact place information because
those reduce learning cost on iOS.

Savvy must diverge wherever the user is deciding what a place means in their own
memory. The drawer, detail actions, social/referral surfaces, review queue, and AI
recommendations should make saved memory, unsaved candidates, source evidence,
lists, and planning actions explicit. The map shell may feel familiar; the memory
layer must feel like Savvy.

## Core Metaphors

### Memo Elephant

Memo is the brand character and memory keeper. Use Memo to signal guidance, sorting,
review, and friendly system intelligence.

Rules:

- Use `MemoMascotMark` for brand moments, onboarding, sign-in, empty states, and
  Passport guidance or brand lockups.
- Memo should not become a random decoration on every row.
- Memo copy should be short and useful: "Memo has 3 clues waiting", not mascot jokes.

### Cream Notebook

The cream notebook is the app canvas. It makes saved memory feel personal and physical
without turning the app into a toy.

Rules:

- Default app surfaces use `saveCream`, `saveNotebookBackground`, or
  `saveNotebookPage`.
- Avoid plain white page backgrounds unless the screen is an OS-provided sheet that
  cannot use the notebook surface.
- Notebook cards use dark ink outlines, restrained shadows, and stable spacing.
- Do not nest decorative cards inside decorative cards. Use cards for real objects:
  Memory Card, Review Candidate, Evidence Receipt, Passport section.

### Map Stamp

A Map Stamp is a confirmed saved place with a reliable map identity.

Rules:

- Only confirmed places and visited places can be Map Stamps.
- Map Stamps may appear as pins.
- Map Stamps use the stamp/seal visual family: `SaveMemoryBadge(.saved)`,
  `PlaceMapPin`, honey or category stamp color, dark ink outline.
- Map Stamp actions can include Navigate, Plan around this, View source, Edit,
  and Delete with explicit confirmation.

### Tile Town (product map base)

**Lock (2026-10-14 founder, via CEO):** product Map uses a
full-pixel tile-town base. Soft Pixel accents-only on MapKit (H1/M1 from
2026-10-13 / PRs #277–#278) is **superseded for the map base**. Do not
silent-partial Soft Pixel: a MapKit atlas with pixel pins is not the lock.
Founder 2026-10-20 abandoned tile-town on Home; Map files stay for the
Map agent.

Rules:

- Product Map tab (`SaveTileTownRootMap`) still renders `SaveTileTownCanvas`.
  Home (`SaveDoodleHomeView`) is the Doodle nearby list + mini-map, not a
  tile-town peek. Friends (`SaveFriendsView`) is a doodle people list; the
  shared map stays hidden.
- Tile-town is a memory map. Pins hash to village lots. It does not silently
  confirm places and it does not invent GPS truth. Navigate / Trip maps may
  still hand off to MapKit or Apple Maps.
- Nearby / Saved / Friends filter chips live on **Map only**. Home must not
  reuse that chrome.
- Coral pins only. Selected stamp elevates to a kraft peek card (name + date/area).
  Source-only clues still have no pin.
- Tile-town is nearest-neighbor integer tiles (`SaveTileTownRaster`): buildings,
  roofs, trees, water, and roads are crisp cells. No anti-aliased vector houses
  or curved roads. Do not blurry-upscale pixel art.
- **2026-10-19/20:** The isometric tile-town Home hero is withdrawn.
  Map stays on the current town renderer until the Doodle Map PR. Pins
  and saved stamps stay tappable on Map.
- App Store frames and product UI share this town. In-app **titles** (Savvy
  wordmark, page titles) use `SavePixelDisplayText` / `SavePixelType`
  (Pixelify Sans Latin + Fusion Pixel CJK). Stamp names stay SF Rounded until
  the shared stamp PR. Body copy stays San Francisco via `SaveAtlasType`.

### Soft Pixel accents (on tile-town)

Soft Pixel is the accent language on top of tile-town and Atlas paper. It
does not replace Atlas tokens, the cream notebook canvas, or the tile-town
map base.

**Lock (2026-10-14 founder):** Soft Pixel appears as pins, Map Stamp seals,
and Memo. Not a full Soft Pixel / 16-bit UI chrome system. The map *base*
is the owned tile-town renderer, not a random `SoftPixel*` / `16-bit` city
PNG and not live MapKit.

Rules:

- Allowed Soft Pixel surfaces: tile-town pin marks, Map Stamp seals
  (`SaveKraftStamp` / `SaveMemoryBadge` stamp family), Memo (`MemoMascotMark`),
  small stamp chips on tickets. Trip MapKit pins may keep `PlaceMapPin` /
  `ReviewCandidateMapPin`.
- Forbidden: Soft Pixel chrome on every inactive root tab; Soft Pixel
  replacing Atlas paper cards, type, or kraft chips wholesale; a one-off
  16-bit city asset as a silent MapKit substitute.
- Root tabs stay production Home / Map / + / Friends / Passport
  (`Primary Navigation`). Tab shell is a flat full-width cream bar
  (`#FFF9EB`) with a hard 2px `#C9AF8B` top rule, 24px pixel line icons,
  coral on the active destination, and a coral `+` circle with no visible
  "Save" label. Not a floating rounded glass capsule. VoiceOver still names
  the capture control.
- Seals never show raw hex, debug IDs, or pipeline tokens in primary UI
  (see Evidence Receipt).
- Stamp language is one system: illustrated pixel stamp art (`SaveKraftStamp`
  / `SaveKraftStampPixelArt`) on Home recent stamps and the Passport grid,
  kraft perforated seal for both. Locked Passport slots show `???`.

### Review Clue

A Review Clue is evidence that Savvy has not promoted into a confirmed memory.

Rules:

- A clue is not a saved place.
- A clue can become a Review Candidate when Savvy has a likely place match.
- A source-only clue must stay out of map-pin state unless it gains reliable
  coordinates.
- Review UI should say what is known, what is missing, and the next action.

### Passport

The Passport is the user’s personal profile and explicit sharing surface. Home owns the full private saved-place library.

Rules:

- Use Passport for profile, language, local memory, saved count, visited count,
  proof-backed count, cities, waiting clues, and account controls.
- Do not label a self-marked visited place as proof-verified. Real-world
  verification requires receipt, photo, or location evidence.
- Proof-backed count stays `0` until Savvy has user-attached proof evidence.
  Public map metadata, friend-saved places, and self-marked Visited status do
  not count as proof.
- Keep Passport as the navigation name; its behavior is a personal profile.
- Passport uses a compact profile header, quests above a shared-post grid, and a separate settings entry.
- Root Passport keeps a bottom inset (`rootTabScrollClearance`) so the bio
  and stamp labels clear the tab bar on landing. Tapping a stamp opens that
  place. Friend author rows open that friend's Passport, including review-demo.
- Passport identity uses the chosen photo saved for the current account on this
  device when available; otherwise it uses `SavvyLogo`. This photo has no cloud
  avatar representation and does not sync between devices.

### Evidence Receipt

An Evidence Receipt shows why Savvy believes an item is what it says it is.

Rules:

- Evidence is supporting content, not the main title.
- Source URL, caption, review count, address clue, and match status belong in an
  Evidence Receipt or compact chips.
- Do not lead a card with "Instagram Reel" when a place name exists.
- Long debug text such as pipeline names, evidence tiers, or raw diagnostics should
  stay out of primary UI.

## Vocabulary

Use these product nouns:

- Savvy
- Memo
- Map Stamp
- Visited Map Stamp
- Review Candidate
- Source Clue
- Waiting Clue
- Memory Card
- Evidence Receipt
- Passport
- Friends (朋友): recent explicitly shared place posts from followed authors
- Your quests (探索任務): live next steps in Passport
- Plan
- Plan around this
- Trip Plan
- Confirm candidate
- Reject clue
- Needs exact place

Avoid these in user-facing UI:

- Egg, hatch, hatching
- Generic "bookmark" as the primary product metaphor
- Generic "profile" when the screen is Passport
- Generic "saved item" when the item is a Map Stamp
- Debug labels as visible product copy
- "Recent Stamps" unless it clearly means recent confirmed Map Stamps
- XP, Level, gems, login-streak calendar, Path / Shop / Progress chrome
- Rewards, currencies, or entitlements granted by completing Passport missions

## Atlas Postcard Tokens

Atlas Postcard is the current visual system for Savvy's primary surfaces. It
reads as an illustrated travel atlas: warm paper panels, native rounded
type, kraft luggage-tag chips, and postage/ticket shapes.

Canonical source of truth is code:

- Production: `SaveAtlasPalette` and `SaveAtlasType` in
  `SAV-E/Extensions/Color+Theme.swift`.
- Prototype twins: `AtlasPalette` and `AtlasType` in
  `Prototypes/AtlasPostcard/Sources/Theme.swift`. The prototype is a
  light-only, fixed-viewport reference. Production tokens are adaptive
  light/dark and Dynamic Type aware (`relativeTo:`). On any mismatch,
  production `SaveAtlasPalette` / `SaveAtlasType` win.

Spec crops that judge "against DESIGN.md Atlas tokens" (for example
`specs/2026-08-04-save-trips-ask-surface-rework-v0.md` P2) mean the tables and
rules in this section.

### Atlas Palette

Hex values below are the `SaveAtlasPalette` values in code. If code and this
table ever disagree, fix whichever one drifted in the same PR.

Token consolidation map (`main` → this PR). Hex values are unchanged.

| Old (`main`) | New token | Light | Dark |
| --- | --- | --- | --- |
| `coral` `Color(light: "F26B4A", dark: "D97861")` | `coralLightHex` / `coralDarkHex` → `coral` | `#F26B4A` | `#D97861` |
| canvas / paper `Color(light: "FFF9EB", dark: "1E1C19")` | `creamHex` / `cream` → canvas / paper | `#FFF9EB` | `#1E1C19` |
| — | `brandCoralHex` / `brandCoral` | `#F26B4A` | `#F26B4A` |
| Pin `Color(red: 0.949, green: 0.420, blue: 0.290)` | `SaveAtlasPalette.brandCoral` | `#F26B4A` | `#F26B4A` |
| Test / Share hex `"F26B4A"` | `SaveAtlasPalette.coralLightHex` | `#F26B4A` | — |

| Role | Token | Light | Dark | Use |
| --- | --- | --- | --- | --- |
| Canvas | `SaveAtlasPalette.canvas` | `#FFF9EB` | `#11161C` | Full-screen Atlas background |
| Paper | `SaveAtlasPalette.paper` | `#FFF9EB` | `#1B2027` | Cards, panels, drawer sheets (`saveAtlasPaper`) |
| Forest | `SaveAtlasPalette.forest` | `#0E4A33` | `#B9E0C9` | Display headings, ticket titles, confirmed accent |
| Ink | `SaveAtlasPalette.ink` | `#2F2E23` | `#F4F1E4` | Primary text, shadows at low opacity |
| Muted | `SaveAtlasPalette.muted` | `#62594F` | `#CFC4B8` | Supporting and secondary copy |
| Coral | `SaveAtlasPalette.coral` | `#F26B4A` | `#D97861` | Postage accent: primary CTA, source-clue state. Matches landing `--coral`. |
| Brand coral | `SaveAtlasPalette.brandCoral` | `#F26B4A` | `#F26B4A` | Non-adaptive `#F26B4A`. App icon, wordmark, and the tile-town pin. Do not recolor assets. |
| Cream | `SaveAtlasPalette.cream` | `#FFF9EB` | `#FFF9EB` | Landing / Atlas cream. Canvas and paper light columns. |
| Mint | `SaveAtlasPalette.mint` | `#D6E8C4` | `#4F7258` | Confirmed / saved state fills |
| Sky | `SaveAtlasPalette.sky` | `#B5E3F5` | `#3F758B` | Review state fills |
| Lavender | `SaveAtlasPalette.lavender` | `#E3D6F7` | `#57466F` | Premium and soft brand accent |
| Kraft | `SaveAtlasPalette.kraft` | `#EADDC6` | `#71543C` | Chips, tags, Passport spine, neutral fills |
| Kraft light | `SaveAtlasPalette.kraftLight` | `#F0E3CA` | `#5A4E3C` | Upper kraft range, stamp fills |
| Honey | `SaveAtlasPalette.honey` | `#FFCC4F` | `#A87328` | Stamp emphasis, highlights |
| Stroke / line | `SaveAtlasPalette.stroke` / `.line` | `#C9AF8B` | `#8A7358` | Hard 2px strokes (`strokeWidth`) |
| Card radius | `SaveAtlasPalette.cardRadius` | `6` | `6` | Default paper corner |

Tile-town materials live in `SaveTileTownPalette` (code wins). Grass `#8FBF6A`,
water `#7EC8E3`, road `#F4E6C8`, roofs coral/honey/sky, house paper `#FFF8E8`.
Do not treat these as Atlas paper substitutes for tickets or chrome. A v5
isometric retune of these cells is a follow-up with the town renderer.

Palette rules:

- Canvas is the page; paper is the object. Panels sit on canvas as
  `SaveAtlasPalette.paper` with a hard `stroke` at `strokeWidth` 2pt
  (`saveAtlasPaper(radius:shadow:)` is the standard treatment; default
  radius is `cardRadius` ~6).
- Forest is the Atlas "brand ink" for headings and ticket titles; body copy
  uses `ink`, support copy uses `muted`.
- State colors keep the legacy nouns: mint means confirmed/saved, sky means
  review, coral means source clue or attention (see `SavePostcardTicketStyle`).
- Shadows come from `ink` at very low opacity (~0.05 to 0.08), never black.
- Dark mode uses the dark column above; do not reuse light pastels as dark
  fills.

### Atlas Typography

`SaveAtlasType` replaces the system-font rules of the legacy section on all
Atlas surfaces. Production type scales with Dynamic Type; display, strong, body, and regular
accept `relativeTo:`, and editorial scales relative to headline.

| Role | Token | Face | Use |
| --- | --- | --- | --- |
| Pixel display | `SavePixelDisplayText` / `SavePixelType` | Pixelify Sans + Fusion Pixel CJK | Savvy wordmark and page titles. OFL. Zpix is not bundled (commercial). Stamp names wait for the shared stamp PR. |
| Pixel chrome | `SavePixelChromeIcon` | 8×8 nearest-neighbor | Retired on the root tab bar. Doodle v1 uses 24pt hand-drawn template icons (`SaveDoodleTabIcon`). |
| Display | `SaveAtlasType.display(_:)` | System Rounded Semibold (SF) | Hero numerals, action labels, display moments |
| Strong | `SaveAtlasType.strong(_:)` | System Rounded Bold | Card/ticket titles, CTAs, uppercased eyebrows with tracking |
| Body | `SaveAtlasType.body(_:)` | System Rounded Medium | Body and detail copy |
| Regular | `SaveAtlasType.regular(_:)` | System Rounded Regular | Captions, subtitles, count labels |
| Editorial | `SaveAtlasType.editorial(_:)` | System Rounded Regular Italic | Editorial brand moments: envelope titles, counts, postcard captions |

Typography rules:

- Eyebrows are `strong` at small sizes, uppercased, with positive tracking
  (~0.65).
- Editorial rounded italic is a garnish for brand moments, not a body face.
- Use `SaveAtlasType` roles for consistent weights and Dynamic Type scaling,
  rather than ad hoc legacy heavy/black text on Atlas
  surfaces. Home uses paper-backed, wrapping place names beneath photographs;
  labels must remain readable when a photo is absent or visually busy.
- With an authorized location, Home orders confirmed places by distance and
  features the nearest. Without a location, it uses the latest confirmed place.
  Asynchronous photo loading must not change which place is featured.
- Home photos use a fixed crop region in both loaded and missing states, with
  paper-backed names and areas beneath every card.

### Kraft Chips

Kraft is the neutral "luggage tag" material for chips and tags on Atlas paper.

- Chip fills use `SaveAtlasPalette.kraft` at 0.24 to 0.72 opacity; text on
  kraft is `ink` or `forest`.
- Strokes use `kraft` or `line`, often dashed (`StrokeStyle(dash:)`) for the
  stitched-tag look.
- Reference implementations: ask drawer chips (`AIDrawerView`), search result
  chips (`SaveSearchResultsComponent`), Passport spine and stat chips
  (`ProfileView`).
- Kraft is neutral. Do not use it to signal state; state fills are mint, sky,
  and coral.

### Postage Accent

Coral is the postage accent and the strongest color on any Atlas surface.

- Primary action: coral fill, white label, `strong` type. Secondary action:
  paper fill, `ink` label, `line` stroke. This pair replaces the legacy
  honey/cream button pair on Atlas surfaces.
- Postage and ticket shapes carry the metaphor: `SavePostcardScallopedRectangle`,
  `SavePostcardSealShape`, and the onboarding postage ticket shapes in
  `OnboardingView`.
- Ticket states come from `SavePostcardTicketStyle`: review = sky, source clue
  = coral, confirmed = mint with forest accents.
- One coral primary per view section. If everything is coral, nothing is the
  action.

### Surface Ownership

| Surface | System |
| --- | --- |
| Home (`SaveDoodleHomeView`) | Doodle Eat/Go list + native mini-map |
| Saves drawer + search results | Atlas |
| Plan (`SavePlanView`) | Atlas |
| Trips (`TripPackViews`) | Atlas |
| Map shell and drawer panel (`SaveTileTownRootMap`, `SaveMapDrawerPanel`) | Tile-town base + Atlas chrome |
| Ask drawer (`AIDrawerView`) | Atlas |
| Onboarding | Atlas |
| Google Takeout import | Atlas (some legacy tokens remain inline) |
| Passport (`ProfileView`, `StatsView`, pet companion card chrome) | Atlas |
| Friends (`SaveFriendsView`) | Doodle people list (shared map hidden) |
| `CategoryPill`, `EmptyStateView`, `RelatedPlaceSourcesPanel` | Atlas |
| Brand accents: pet preset colors (Spark = honey), stamp moment ripple, `SaveMemoryBadge` stamp palette, `MemoMascotMark` | Intentional — do not recolor in migrations |
| App Clip shared place, trip, and list previews | Atlas |
| `SaveMemoryBadge` chrome, `EvidenceLinkList` (debug-only), smoke harness | Legacy cream-notebook |

Rules:

- New work on an Atlas surface uses Atlas tokens only. Do not introduce new
  `save*` pastel usage there.
- Legacy tokens on a mixed surface are migration debt, not precedent.
- Moving a legacy surface to Atlas is fine; update the table above in the same
  PR.

## Legacy Cream-Notebook Tokens (legacy surfaces only)

> Legacy: applies only to the legacy cream-notebook surfaces listed in
> "Surface Ownership" above. Do not use these tokens for new work on Home,
> Saves, Trips, Map, or the ask drawer — those are Atlas Postcard surfaces.

Use current SwiftUI tokens from `SAV-E/Extensions/Color+Theme.swift`.

| Role | Token | Light | Dark | Use |
| --- | --- | --- | --- | --- |
| Notebook background | `saveNotebookBackground` | `#FFF5E7` | `#101419` | Full-screen app canvas |
| Cream surface | `saveCream` | `#FFF5E7` | `#15191F` | Warm field notebook base |
| Notebook page | `saveNotebookPage` | `#FFF0DC` | `#1B2027` | Cards, sheets, drawer panels |
| Ink | `saveInk` | `#3A2415` | `#FFF8ED` | Primary text and outlines |
| Cocoa | `saveCocoa` | `#3A2415` | `#F7EFE5` | Dark secondary ink |
| Muted text | `saveMutedText` | `#7A5D45` | `#CFC4B8` | Supporting labels |
| Honey | `saveHoney` | `#FFD66B` | `#986724` | Primary action, Map Stamp emphasis |
| Sky | `saveSky` | `#8FCAEA` | `#3F7F97` | Review, search, secondary context |
| Mint | `saveMint` | `#C8EBCF` | `#4F7D5D` | Confirmed, saved, success |
| Signal/coral | `saveSignal` / `saveCoral` | `#EE9C78` | `#9F523F` | Waiting, attention, review |
| Pink | `savePink` | `#F6C1CB` | `#96586B` | Friendly accent, trip support |
| Blush | `saveBlush` | `#FFF6F8` | `#281A20` | Mascot-led onboarding, soft brand warmth |
| Lavender | `saveLavender` | `#DCC8FF` | `#44345F` | Pro/upgrade preview, premium support accent |
| Leaf | `saveLeaf` | `#D9F2C7` | `#435F3D` | Gentle saved-memory support distinct from success mint |
| Blue ink | `saveBlueInk` | `#315D76` | `#BEE7F8` | Cool contrast for review/search copy or icons |
| Disabled | `saveDisabled` | `#D7C0A6` | `#4E4842` | Disabled controls |
| Notebook line | `saveNotebookLine` | `#3A2415` | `#6E6257` | Strokes, dividers, notebook grid |
| Notebook spine | `saveNotebookSpine` | `#F6C181` | `#7A5533` | Passport and notebook binding |

Palette rules:

- Cream is the dominant base, not yellow.
- Honey is an action/accent, not a background wash for every card.
- Mint means saved or successful.
- Sky means review/search/investigation context.
- Signal means attention, waiting, or risk.
- Blush, lavender, leaf, and blue ink should break up the one-note cream/honey
  palette in brand moments, onboarding, and upgrade previews. Do not use them
  to recolor every operational surface.
- Ink outlines should stay visible. If a surface cannot handle a 1.4 to 2 pt ink
  stroke, the surface is probably too small or too decorative.
- Dark mode keeps the same nouns, but uses charcoal surfaces and muted accents.
  Do not reuse fixed light pastels for dark fills.

## Typography

> Legacy: system typography applies to legacy cream-notebook surfaces only.
> Atlas surfaces use `SaveAtlasType` (see "Atlas Typography" above).

Savvy uses native system typography.

Rules:

- Prefer SwiftUI system fonts with heavy weights and rounded design where it fits:
  `.font(.system(size: ..., weight: .black, design: .rounded))`.
- Use `.title2` or `.title3` for screen-level native headings. Avoid oversized hero
  type inside dense app surfaces.
- Use `.headline.weight(.black)` for card titles.
- Use `.caption.weight(.black)` or `.caption2.weight(.black)` for status stamps.
- Body copy should be readable and short. Evidence copy can wrap, but titles should
  not be replaced by evidence.
- Letter spacing stays default.

## Shape, Stroke, Spacing

Base shape rules:

- Small controls: 12 to 14 pt corner radius.
- Object cards: 16 to 18 pt corner radius.
- Large notebook or Passport panels: 20 to 22 pt corner radius.
- Primary outlines: `saveNotebookLine`, 1.4 to 2 pt.
- Map Stamp selected outlines can reach 3 pt.
- Touch targets should be at least 44 pt high.

Spacing rules:

- Compact rows: 8 to 10 pt internal spacing.
- Cards: 12 to 18 pt padding.
- Sheet sections: 14 to 16 pt vertical rhythm.
- Keep one-handed actions near the bottom in drawers and sheets.

## Components

### Memo Mark

Source: `SAV-E/Views/Shared/MemoMascotMark.swift`.

Use for:

- Sign-in hero.
- Onboarding.
- Empty states.
- Passport guidance or a brand lockup, but not the account-avatar fallback.
- Small brand lockup in top map navigation.

Do not use for:

- Every list row.
- Error icons where a concrete system symbol is clearer.

### Memory Badge

Source: `SAV-E/Views/Shared/SaveMemoryBadge.swift`.

States:

- `clue`: source-only clue.
- `ready`: Review Candidate.
- `saved(category)`: Map Stamp.

Do not introduce new badge states without updating this document first.

### Shared Primitives

Source: `SAV-E/Extensions/Color+Theme.swift`.

- Use `saveNotebookSurface` for drawer/detail panels that belong to Savvy's
  memory layer.
- Use `SaveIconTile` for small icon-only controls and row icons.
- Avoid ad hoc circular icon buttons inside Passport, detail drawers, and
  notebook cards unless the object is explicitly a map pin or avatar.
- Avoid `.ultraThinMaterial` as the primary drawer/card surface for memory UI;
  use notebook surfaces with visible ink strokes.

### Map Pins

Source: product Map uses `SaveTileTownPinMark` on `SaveTileTownCanvas`.
Trip / Navigate MapKit still uses `SAV-E/Views/Map/MapView.swift`.

Rules:

- Product Map pins are coral teardrops. Selected stamp elevates to a kraft
  peek card. Do not invent a six-color pin rainbow.
- Trip MapKit confirmed places use `PlaceMapPin`: compact forest category
  symbols; a checkmark means user-marked Visited. A selected stamp gains the
  honey focus ring.
- Review candidates retain a question mark and dashed sky outline at rest.
  Unsaved search results use paper category pins; shared places use a people symbol.
  Never reduce these states to anonymous dots.
- Review candidates use `ReviewCandidateMapPin` only when coordinates are reliable.
- Source-only clues do not get pins.
- Pins need accessibility labels that include the state, such as "Map Stamp" or
  "Review Candidate".

### Memory Card

A Memory Card is the user-facing card for a confirmed Map Stamp.

Required hierarchy:

1. State badge: Map Stamp or Visited Map Stamp. Want to try and Visited are
   Map Stamp substates. Show them as kraft (Want to try) or mint (Visited)
   chips next to the Confirmed Map Stamp seal. Do not add a `SaveMemoryBadge`
   case.
2. Place name.
3. Address or area.
4. Short memory summary.
5. Compact chips: category, rating, source, map confirmed.
6. Evidence Receipt collapsed or compact.
7. Primary actions.

### Review Candidate Card

A Review Candidate is an unresolved place match.

Required hierarchy:

1. Candidate name or best known label.
2. State: Review Candidate.
3. Known clues.
4. Missing information.
5. Evidence Receipt.
6. Confirm, reject, or find exact place action.

### Source Clue Row

A Source Clue preserves weak evidence without pretending it is a place.

Required hierarchy:

1. Source platform or source label.
2. What Savvy extracted.
3. Missing exact place.
4. Action: Find exact place or keep as clue.

### Evidence Receipt

Required content when available:

- Source platform.
- Source URL or source label.
- Caption clue.
- Address clue.
- Review count.
- Match confidence or missing info.
- Whether coordinates are reliable.

Evidence Receipt should be compact by default. Expanded evidence belongs in a detail
view or disclosure, not in every card body.

### Passport

Source: `SAV-E/Views/Profile/ProfileView.swift`.

Required root content, in order:

1. Account identity, real post/following/follower counts and edit/settings actions.
2. Owner stamp collection: coral progress and kraft `SaveKraftStamp` grid,
   including at least one locked `???` slot while the page is incomplete.
3. Owner-only Your quests, at most three existing live next steps. Hide if empty.
4. Shared places: explicit new-post action, All / Want to go / Visited filters,
   three-column post grid (adapt at accessibility text sizes).

Tapping a post opens its detail; the owner can edit or withdraw. Only explicit
shares appear here. Home retains the full private collection and review queue.
The settings route retains the collection ledger, activity, language, private
memory controls, sharing/privacy, Pro, tutorial and account controls. Existing
lists remain reachable. No XP, rewards or entitlement changes.

## State Model

Every UI object must map to one of these states:

| State | Meaning | Can show on map? | Primary action |
| --- | --- | --- | --- |
| Source Clue | Savvy preserved source evidence but lacks a confirmed place | No | Find exact place |
| Review Candidate | Likely place match, user confirmation needed | Only with reliable coordinates | Confirm or reject |
| Unsaved Candidate | Recommendation or visible map object not saved | Optional if map-originated | Save or inspect |
| Map Stamp | Confirmed saved place | Yes | Navigate or plan |
| Visited Map Stamp | Confirmed place with visited memory | Yes | Update memory |
| Private Review | User review proof or note, private by default | No by itself | Add proof |
| Trip Stop | Route/planning object, not necessarily saved | In trip context only | Review plan |
| Travel window | Arrival, departure, check-in, or check-out constraint on a Trip Plan | No pin of its own | Adjust time |

Never collapse Source Clue, Review Candidate, and Map Stamp into one visual state.

## Screen Rules

### Primary Navigation

- Root controls are Home / Map / + / Friends / Passport, in that order.
- Tab bible: flat full-width cream bar (`canvas`) with a hard 2px `stroke`
  top rule; 24pt hand-drawn template icons (`SaveDoodleTabIcon`: house,
  folded map, plus, people, booklet); coral on the active destination only,
  muted when idle; the center `+` is a coral (`SaveAtlasPalette.coral`) circle with no visible "Save" label, but VoiceOver and `root.tab.save` keep the capture
  name. **DESIGN question:** the 2026-10-19 packet asked for a red `+`
  circle; this PR keeps production coral until that token is decided. Do
  not use a mint selection pill or a floating glass capsule.
- Home owns waiting clues and the nearby Eat/Go list. The mini-map is an
  index; tapping it opens Map with the same city and Eat/Go filter. Review
  clues stay on the one-line `N clues waiting · Review` entry when N>0.
  Collected opens Passport. Saves remains a child of Review / existing
  library routes — Home no longer shows a See all saves row. Do not add a
  duplicate Saves tab. Trips stay a production child reached from Saves as
  `Trips ›` (HoP acceptance H-6).
- + opens capture and leaves the previous destination selected when dismissed.
- Plan is a secondary route while planning demand remains unvalidated.
- Trips remain a child route. Home no longer shows a More menu.
- Planning and trip child pages have a back path to their parent. Plan has no
  root tab bar; the conversation remains owned by the app shell across visits.

### Home (Doodle v1)

Home exposes a visible 44pt-minimum Saves control when no clues are
waiting. Test-only or invisible navigation controls are not valid user
routes. When clues wait, Review is that route. Visited Home/Map stickers
use the official DESIGN color die-cut (duck, noodle, coffee, temple,
lantern); unvisited stickers use the matching pencil outline.
The elephant is brand-only — wordmark and the empty Home plate — and
is never a place sticker. Code-drawn geometry is not a place sticker.
Art sits in a 48pt box at ≤40pt.

Resting Home is Savvy + Eat/Go in the header, then the city, clues,
native mini-map, nearby own-saves rows, then Collected. It is not the
Map tab.
Nearby / Saved / Friends chips must not appear here.

HoP locked D2 (city switcher) and D3 (Eat/Go + nearby own-saves) on
2026-10-19. The 2026-10-14 tile-town Home chrome (quiet search, Trips /
Saves / More header icons, tile-town peek, recent stamps) is superseded
on Home only. Founder 2026-10-20: tile-town is abandoned; Home ships
Doodle only. Map and Passport keep their current town lock until their
Doodle PRs.

Eat shows only Eat (food, cafe, bar). Go shows only Go (attraction, stay,
shopping). The list is the user's own saves near the selected city or
current location, sorted by distance. No discovery feed. Tapping the
mini-map opens Map with the same filter and city.
Near you header, Collected, and Passport share one city: the nearest
save across every category, not the nearest Eat/Go row. Fallback
addresses use the locality (Berkeley), not a state+ZIP fragment.
European postcode-first lines (`8001 Zürich`) parse as the city.
Stable city IDs keep a region qualifier so Springfield IL and
Springfield MA stay apart; the picker still shows the locality.
Collected X/Y is visited / all saved places in the current city scope,
every category. Eat/Go and the listed row count do not change it;
switching city does. When the Eat/Go list is empty but the city still
has saves, keep the Collected strip and show a filter-empty message
instead of the whole empty Home. The strip opens Passport with the same
city numbers (HoP 2026-10-21). Unknown location is not worldwide nearby.

Location denied: hide "Near you", show the last city sorted by most
recent save, and prompt to allow location. Empty nearby: Caveat title,
coral + Save link, and a latest-save jump when another city has saves.

Clues stay on the one-line Review entry when N>0. Home no longer shows
`See all saves`. Review (`home.review`) still opens the existing Saves
screen when N>0. Saves reaches Trips from its header as `Trips ›`
(`saves.trips`) — HoP acceptance H-6. Do not add a second Home Trips
row. Collected opens
Passport. Wordmark is Caveat SemiBold 34; the city line is Caveat 20 with
a 2pt coral underline under the city word only. Body copy stays
`SaveAtlasType`. The visual reference is the Codex packet and spec §8,
not DESIGN v2 Home. H1–H4 CI rasters are judged manually by DESIGN;
the 0.90 visual-parity score is not evidence. Historical DESIGN v2
`design/doodle-targets-2026-10-20/home-light.png` at `eade369`
(exact 402×874; `home-dark.png`; `home-mask.png` white = ignore)
is archive only. v1 is retired.

### Sign-In

First impression:

- Memo elephant as clear brand anchor.
- Savvy name prominent.
- One sentence: "Your personal place agent."
- Workflow strip: Capture, Review, Save.
- Cream notebook background.

### Onboarding

Teach the state ladder:

```text
Source Clue -> Review Candidate -> Map Stamp -> Trip Plan
```

Use one interactive example. Do not add a marketing page. Start in the device or
previously selected language; language selection is an optional sheet. The selected
Source to Memory direction uses one photo postcard throughout three stages: source,
review, saved preview. Source is explicitly a clue, review is sky with confirmation,
and the saved preview is mint and labeled as an example. The cafe is fictional;
no real coordinates or storage writes are implied by the demo.

Personal input is a separate first-run sheet, reachable immediately or after the
example. Its CTA hands the draft to the existing account-scoped capture flow after
sign-in; nothing is analyzed or saved by onboarding. Every skip and replay completion
returns no clue. Never show the fictional cafe as the result of a user's own input.
Keep primary and visible skip actions in the bottom safe area with 44 pt targets;
long content scrolls above them. Passport offers a replay using only the sample,
with a visible close action. Replay never resets onboarding completion, captures
private input, or adds a place.

### Map

The map is the spatial memory canvas. The product Map tab is tile-town, not
live MapKit.

Rules:

- Map chrome: Savvy wordmark + Nearby / Saved / Friends kraft chips. Those
  three chips are Map-only, 44pt buttons (`map.lens.*`), and stay below the
  48pt status band. The search drawer never covers them: large stop ends
  below `SaveTileTownProductLock.mapChromeHeight`, and only the visible
  paper hits so pins stay tappable through medium. Home's shared Eat/Go +
  city (`SaveDoodleSession`) apply to Saved/Nearby pins only when Map opens
  from the Home mini-map. Opening the Map tab directly keeps the unfiltered
  Saved/Nearby/Friends default. After a mini-map handoff, Map Eat/Go chips
  (`map.eat` / `map.go`) and the city control (`map.city`) can change that
  shared state.
- The town canvas pans with a drag. Pin tap selects the kraft peek card.
- Drawer search (collapsed capsule) still opens the parked search panel.
  Category, Want to try, Visited, and Nearby-distance chips may remain in
  the drawer as Map Stamp lenses; they are not Home chrome.
- Only reliable states get pins on the town. Source-only clues have no pin.
- Unsaved nearby candidates are shown only after an explicit drawer action.
- Selected stamp shows a kraft peek (name + date/area), not a default card
  at rest.
- Tapping the collapsed search shelf opens the existing full-height panel,
  focuses the search field, and shows the keyboard.
- Dragging the handle or panel resizes through parked stages and must not
  request keyboard focus. Tapping the resize handle remains a resize control.
- Trip maps and Navigate may still use MapKit / Apple Maps. That is not the
  product Map base.

### Plan

Use a single conversation with typed itinerary previews, following the interaction
pattern in Anthropic's commerce-agent reference. Keep the Atlas palette and native
SwiftUI components. Each response shows a compact unsaved draft with at most three
day previews; complete stops, travel checks, candidate confirmation, and explicit
Save as Trip expand inline in the same Plan surface. The chat input stays accessible while chatting.
Conversation turns remain available for follow-up requests. This is a presentation
pattern, not adoption of the reference demo's backend or payment architecture.

Plan is the itinerary workbench. It drafts a walking day from confirmed Map Stamps.

Rules:

- Plan is a child page reached from Trips or an explicit place action.
- Every Plan turn reaches the semantic planner with the current draft and bounded
  place inventory. The model chooses a draft edit, one necessary clarification,
  or one nearby candidate lookup; no required pace/time questionnaire.
- A clear destination is enough for a first provisional draft. Unspecified duration,
  pace and clocks may use a disclosed one-day, balanced, 09:00–21:00 assumption.
  Never invent a city. Explicit user conditions override these editable defaults.
- Natural-language edits can select, replace, remove, reorder and reschedule stops.
  Day patches preserve omitted days exactly. A changed global condition requires
  all affected days. Only known place references and valid, nonoverlapping times
  pass validation; the model gets bounded correction feedback before any mutation.
- Candidate lookup is limited to one nearby search per turn, anchored to a saved
  place in the requested area. At most three model decisions run per turn.
  Search results remain unconfirmed. Failed edits keep the previous draft and input.
- A country-only request retains its duration and asks for a city. An unknown or
  unsupported city never falls back to an unrelated saved city. Keep the prior
  unsaved draft while clarifying or recovering from a failure.
- Requested days remain visible even when some need more places. Place identity
  comes from local inventory, never generated names or IDs. Travel and opening-hour
  uncertainty remains visible; the agent must not claim bookings or verified hours.
- Place actions open this same Plan conversation. Plan around this stages the
  exact place without submitting. Add to Trip offers eligible existing trips
  and a new-plan choice inline; only an explicit existing-trip selection writes
  that place to the chosen trip. Saved trips remain accessible from Plan.
- New trip and Saved trips stay visible above the Plan conversation. Saved trips
  appear inline and open directly into the selected trip, without another landing page.
- New trip clears conversation conditions and messages. An unsaved draft requires
  discard confirmation; saved trips are always retained. No calendar or manual form.
- Trips has a New trip action, with no second planning composer. Planning questions
  and missing-condition clarification belong only in Plan.
- A reply of no preference accepts provisional choices and proceeds; it does not
  trigger another mandatory question about optional clocks.
- Confirmed Map Stamps are the only stops that can be saved into a Trip.
- Unsaved attractions, meals, or hotels appear as Unsaved Candidates (sky), never as Map Stamps.
- Travel windows (arrival, departure, check-in, check-out) are Trip Stop constraints, not places.
- Savvy does not book flights or hotels. Missing lodging is a gap, not a fake reservation.
- Five-second test: Map Stamp, Unsaved Candidate, and travel window must be distinct.

### Drawer

The drawer is Savvy's command and memory workbench.

Rules:

- Map drawer is a docked place-search surface: saved places and public map results. It does not expose the Ask assistant or mic.
- The drawer may use translucent system material in map mode so the map remains the
  primary visual surface.
- Any remaining assistant dictation is outside the Map search surface.
- Required mic states: idle, requesting permission, listening, transcribed,
  loading, permission denied, unavailable, and failed.
- Map filters belong in the drawer so the map remains clean; conversational planning belongs in Plan.
- Category chips stay in the drawer. After them, Want to try, Visited, and
  Nearby may filter confirmed Map Stamps. Nearby is a 2 km saved-place lens.
  It does not pin unsaved candidates. Do not add restroom, gas, or wildlife
  chips.
- Idle drawer content should use an Apple Maps-like hierarchy: command bar, quick
  action rows, filters, recent items, and suggestions. Do not show the full agent
  command console by default.
- Separate "From your Savvy" from "New / Unsaved".
- Confirmed memory must visually beat recommendations.
- Empty states need a next action.
- Disabled rows must look disabled, not broken.

### Place Detail

Place detail is a Memory Card detail, not a receipt dump.

Rules:

- Place identity first.
- Evidence second.
- Add to Trip is the one coral primary. Plan around this sits beside it as a
  paper secondary. Do not restyle Plan around as honey or a second coral
  button.
- Edit and Delete are direct text actions, secondary to planning. Delete always
  requires explicit confirmation. Do not hide them in a generic More menu.
- Visibility controls belong in Profile; they are not a second detail menu.
- Source link clickable when available.

### Review Queue

Review queue is Memo's waiting clues.

The full queue is a compact continuous list on Atlas canvas, with paper rows,
readable counts, and explicit source-clue versus review-candidate labels.
Use the native navigation title once. Do not interrupt the list with an oversized
envelope, repeated mascot header, or decorative count panel.

Rules:

- Show count and severity.
- Explain known vs missing.
- Confirm/reject actions are explicit.
- Block fake coordinates.

### Passport

Passport is the user's personal profile, stamp collection, and sharing
manager. The owner root shows a coral progress bar (`saved/goal`) and a
kraft stamp grid that shares `SaveKraftStamp` with Home recent stamps.
Locked slots show `???`. Quests stay above shared posts, visible only to
the owner. A visitor passport contains only currently accessible explicit
posts and a minimal author identity; no tasks or private memory totals. The
owner sees paused posts as paused, not silently published.

Daily activity stays in settings with the collection ledger. Count confirm/save/
new Visited transitions once per local day; not logins, rewards or attendance
proof. Visited never means evidence-verified. No private notes, imported reviews,
source clues or visit timestamps appear in post projections.

### Friends

Home / Map / + / Friends / Passport remains the root bar. Friends is
people-first doodle: Caveat / Iansui “Friends” / 「朋友」 title, ink
outline “Invite”, forest-ring avatars (initial or photo), author name,
“last at Place · 2d”, and right-side 40pt doodle stickers
(coffee / noodle / lantern / hill). The shared map stays hidden (HoP; cut in DESIGN v1 and kept).
The visual reference is Codex packet spec §7.4. Live `five-tab-friends`
gates at 0.90 against `ProductionTargets/friends.png` with no mask.
This surface has no animation (F-B11). An
author opens a read-only passport under the same live follower audience gate.
Loading, retry, empty and withdrawn states are explicit; sample activity exists
only in isolated UI fixtures. A follow or private memory update never publishes.

A post may represent Want to go or Visited. Caption is optional; a rating is
optional and allowed only for Visited. Post status is the author's explicit
snapshot, independent of later private place changes. Category artwork is used
when no safe shared image exists; do not publish private photos automatically.
Users may explicitly attach up to three photos in the post composer, preview or
remove them, and publish them with the post. Photos inherit the live follower
audience and withdrawal boundary; attaching a photo does not mark a visit as
proof-verified. Original photo metadata is excluded from shared attachments.

Sharing explicitly opts into the existing one-way follower audience, labeled
“Visible to people who follow you” / “追蹤你的人可見”. Withdrawal stops the follower
post and its live attribution, while preserving owner and recipient saved places.
Separately published public links/cards retain their own consent lifecycle; the
withdrawal confirmation states this. Recipient saves are idempotent and never
copy author notes or ratings or overwrite recipient memory. Legacy restaurant
rating withdrawals remain available in Sharing & Privacy.

### Share Extension

Share Extension is a quick capture surface.

Rules:

- No bottom tab bar.
- No full app chrome.
- Show capture status, extracted clues, and next action.
- If confidence is weak, save as clue or Review Candidate, not Map Stamp.

## Accessibility

- Touch targets: minimum 44 pt.
- Buttons must have labels and hints when the icon is not obvious.
- Dynamic Type should not break core actions. Use wrapping over truncating for place
  names and evidence.
- Status cannot rely on color alone. Use text labels and symbols.
- Cream and muted text must preserve contrast. Use `saveInk` for primary content.

## Implementation Rules

- Before any visual PR, read this file and check changed screens against it.
- New product nouns need to be added here before they are added to UI copy.
- New color tokens must be added to `Color+Theme.swift` and this file in the same PR.
- Do not introduce web mockups as implementation artifacts for the native app.
- Do not add speculative states, badges, or metaphors.
- If a screen needs a new state, update the State Model first.

<!-- ci: pull_request required-check tip 20260922T184802Z -->
