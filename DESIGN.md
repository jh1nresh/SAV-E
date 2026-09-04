# Savvy Design System

> Last updated: 2026-09-04
> Status: source of truth for native iOS design work
> Token systems: **Atlas Postcard** governs Home, Saves, Trips, Map, and the ask
> drawer. **Cream-notebook** tokens are legacy-surface-only. See "Atlas Postcard
> Tokens" and "Legacy Cream-Notebook Tokens" below.

## Product Frame

Savvy is a personal place-memory agent. Users send messy place signals: links, posts,
screenshots, notes, maps, imports. Savvy preserves the source, identifies the real
place when it can, asks before saving uncertain matches, and turns confirmed places
into a map-ready memory.

The app is not a generic travel bookmark manager. It is the user's field notebook
for place memory, evidence, and review.

Assumptions locked by current code:

- Native app is SwiftUI and MapKit, not React or web UI.
- `Color+Theme.swift` owns the current palette tokens.
- `MemoMascotMark` owns the Memo elephant mark.
- `SaveMemoryBadge`, `PlaceMapPin`, and `ReviewCandidateMapPin` define the current
  visual split between clues, review candidates, and Map Stamps.
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
  Passport identity.
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
- Map Stamp actions can include Navigate, Plan around this, View source, and Delete
  in overflow.

### Review Clue

A Review Clue is evidence that Savvy has not promoted into a confirmed memory.

Rules:

- A clue is not a saved place.
- A clue can become a Review Candidate when Savvy has a likely place match.
- A source-only clue must stay out of map-pin state unless it gains reliable
  coordinates.
- Review UI should say what is known, what is missing, and the next action.

### Passport

The Passport is the user's memory archive and control surface.

Rules:

- Use Passport for profile, language, local memory, saved count, visited count,
  proof-backed count, cities, waiting clues, and account controls.
- Do not label a self-marked visited place as proof-verified. Real-world
  verification requires receipt, photo, or location evidence.
- Proof-backed count stays `0` until Savvy has user-attached proof evidence.
  Public map metadata, friend-saved places, and self-marked Visited status do
  not count as proof.
- Do not call it a profile unless referring to the implementation file.
- Passport should look like a notebook cover plus stamp ledger, not a settings table.

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
- Today on Savvy
- Plan around this
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
- XP, Level, gems, login-streak calendar, quest board, Path / Shop / Progress chrome
- Rewards, currencies, or entitlements granted by completing Passport missions

## Atlas Postcard Tokens

Atlas Postcard is the current visual system for Savvy's primary surfaces. It
reads as an illustrated travel atlas: warm paper panels, condensed editorial
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

| Role | Token | Light | Dark | Use |
| --- | --- | --- | --- | --- |
| Canvas | `SaveAtlasPalette.canvas` | `#FDF8F3` | `#11161C` | Full-screen Atlas background |
| Paper | `SaveAtlasPalette.paper` | `#FFFDF7` | `#1B2027` | Cards, panels, drawer sheets (`saveAtlasPaper`) |
| Forest | `SaveAtlasPalette.forest` | `#0E4A33` | `#B9E0C9` | Display headings, ticket titles, confirmed accent |
| Ink | `SaveAtlasPalette.ink` | `#2E2117` | `#FFF8ED` | Primary text, shadows at low opacity |
| Muted | `SaveAtlasPalette.muted` | `#62594F` | `#CFC4B8` | Supporting and secondary copy |
| Coral | `SaveAtlasPalette.coral` | `#F26B4A` | `#D97861` | Postage accent: primary CTA, source-clue state |
| Mint | `SaveAtlasPalette.mint` | `#D6E8C4` | `#4F7258` | Confirmed / saved state fills |
| Sky | `SaveAtlasPalette.sky` | `#B5E3F5` | `#3F758B` | Review state fills |
| Lavender | `SaveAtlasPalette.lavender` | `#E3D6F7` | `#57466F` | Premium and soft brand accent |
| Kraft | `SaveAtlasPalette.kraft` | `#F0CFA1` | `#71543C` | Chips, tags, Passport spine, neutral fills |
| Honey | `SaveAtlasPalette.honey` | `#FFCC4F` | `#A87328` | Stamp emphasis, highlights |
| Line | `SaveAtlasPalette.line` | `#A68F78` | `#807365` | Hairline strokes, postmark linework |

Palette rules:

- Canvas is the page; paper is the object. Panels sit on canvas as
  `SaveAtlasPalette.paper` with a `line` stroke at roughly 0.28 to 0.70
  opacity (`saveAtlasPaper(radius:shadow:)` is the standard treatment).
- Forest is the Atlas "brand ink" for headings and ticket titles; body copy
  uses `ink`, support copy uses `muted`.
- State colors keep the legacy nouns: mint means confirmed/saved, sky means
  review, coral means source clue or attention (see `SavePostcardTicketStyle`).
- Shadows come from `ink` at very low opacity (~0.05 to 0.08), never black.
- Dark mode uses the dark column above; do not reuse light pastels as dark
  fills.

### Atlas Typography

`SaveAtlasType` replaces the system-font rules of the legacy section on all
Atlas surfaces. All production variants accept `relativeTo:` for Dynamic Type.

| Role | Token | Face | Use |
| --- | --- | --- | --- |
| Display | `SaveAtlasType.display(_:)` | AvenirNextCondensed-DemiBold | Hero numerals, action labels, display moments |
| Strong | `SaveAtlasType.strong(_:)` | AvenirNextCondensed-Bold | Card/ticket titles, CTAs, uppercased eyebrows with tracking |
| Body | `SaveAtlasType.body(_:)` | AvenirNextCondensed-Medium | Body and detail copy |
| Regular | `SaveAtlasType.regular(_:)` | AvenirNextCondensed-Regular | Captions, subtitles, count labels |
| Editorial | `SaveAtlasType.editorial(_:)` | Georgia-Italic | Editorial brand moments: envelope titles, counts, postcard captions |

Typography rules:

- Eyebrows are `strong` at small sizes, uppercased, with positive tracking
  (~0.65).
- Editorial Georgia italic is a garnish for brand moments, not a body face.
- Do not mix `SaveAtlasType` faces with the legacy heavy rounded system fonts
  on the same surface.

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
| Home (`SaveRootViews`) | Atlas |
| Saves drawer + search results | Atlas |
| Trips (`TripPackViews`) | Atlas |
| Map shell and drawer panel (`MapView`, `SaveMapDrawerPanel`) | Atlas |
| Ask drawer (`AIDrawerView`) | Atlas |
| Onboarding, Google Takeout import | Atlas (migration mostly done; some legacy tokens remain inline) |
| Passport (`ProfileView`, `StatsView`, pet companion card chrome) | Atlas |
| `CategoryPill`, `EmptyStateView`, `RelatedPlaceSourcesPanel` | Atlas |
| Brand accents: pet preset colors (Spark = honey), stamp moment ripple, `SaveMemoryBadge` stamp palette, `MemoMascotMark` | Intentional — do not recolor in migrations |
| `SaveMemoryBadge` chrome, `EvidenceLinkList` (debug-only), Clip preview, smoke harness | Legacy cream-notebook |

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
- Passport hero.
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

Source: `SAV-E/Views/Map/MapView.swift`.

Rules:

- Confirmed places use `PlaceMapPin`.
- Review candidates use `ReviewCandidateMapPin` only when coordinates are reliable.
- Source-only clues do not get pins.
- Pins need accessibility labels that include the state, such as "Map Stamp" or
  "Review Candidate".

### Memory Card

A Memory Card is the user-facing card for a confirmed Map Stamp.

Required hierarchy:

1. State badge: Map Stamp or Visited Map Stamp.
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

Required content:

- Memo identity.
- Passport name.
- Map Stamps count.
- Visited count; proof verification is a separate future evidence state.
- Cities count.
- Waiting clues count.
- Member since.
- Field streak: consecutive local days with a real memory action (confirm a waiting clue, save a Map Stamp, or mark Visited). Not a login check-in calendar.
- Collection: Map Stamps, Visited, Cities, and Waiting clues as memory progress, not a reward track.
- Today on Savvy: at most three live incomplete next steps, including a return step when an unvisited Map Stamp exists. Hide the whole strip when none apply. Not a quest board.
- Language and local memory controls.

Passport section order on the root tab:

1. Hero (Memo + passport name)
2. Field streak
3. Collection
4. Today on Savvy
5. Control pocket

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

Never collapse Source Clue, Review Candidate, and Map Stamp into one visual state.

## Screen Rules

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

Use one interactive example. Do not add a marketing page.

### Map

The map is the spatial memory canvas.

Rules:

- Map top controls stay empty by default.
- Map mode should not force light or dark. It follows the user's system appearance.
- Persistent top-left/top-right map chrome should stay empty unless a real contextual
  signal, such as weather, is wired.
- Passport opens from the drawer command bar, not from persistent map chrome.
- Category filters live in the drawer, not as a persistent map rail. Want to
  try, Visited, and Nearby are drawer chips that filter Map Stamps on the map.
- Current location remains bottom-right and one-handed.
- Only reliable states get pins.
- Unsaved nearby candidates are shown only after an explicit drawer action.

### Drawer

The drawer is Savvy's command and memory workbench.

Rules:

- Collapsed drawer is the primary command bar: text input, mic input, and submit.
- The drawer may use translucent system material in map mode so the map remains the
  primary visual surface.
- Mic is push-to-talk dictation into the same command field, not a separate voice
  assistant mode.
- Required mic states: idle, requesting permission, listening, transcribed,
  loading, permission denied, unavailable, and failed.
- Filters and quick prompts belong in the drawer so the map remains clean.
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
- Destructive actions in overflow.
- Source link clickable when available.

### Review Queue

Review queue is Memo's waiting clues.

Rules:

- Show count and severity.
- Explain known vs missing.
- Confirm/reject actions are explicit.
- Block fake coordinates.

### Passport

Passport is the user's memory ledger.

Rules:

- Keep settings subordinate to memory stats.
- Local Memory debug surfaces must not dominate the default Passport.
- Waiting clues should be visible but not alarming.
- Cities come from saved place addresses.
- Visited comes from places the user marked as visited; do not imply Savvy has
  verified real-world attendance without proof evidence.
- Proof-backed is a separate slot from Visited. It remains `0` until receipt,
  original photo, or location evidence can be attached by the user.
- Field streak sits after the hero and before Collection. Count only confirm /
  save Map Stamp / mark Visited days. Opening the app does not count. Do not
  render a streak month calendar, XP bar, or gem balance.
- Collection is the stamp ledger reframed as memory progress: Map Stamps,
  Visited, Cities, Waiting clues. It does not unlock rewards.
- Today on Savvy sits after Collection and before the control pocket.
  It may observe a waiting clue, an unvisited Map Stamp, a private Map Stamp,
  or a missing friend connection. It does not grant Pro, XP, or rewards. If no
  live step applies, hide the strip. Do not show an empty quest card.

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
