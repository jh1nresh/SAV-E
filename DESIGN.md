# SAV-E Design System

> Last updated: 2026-05-27
> Status: source of truth for native iOS design work

## Product Frame

SAV-E is a personal place-memory agent. Users send messy place signals: links, posts,
screenshots, notes, maps, imports. SAV-E preserves the source, identifies the real
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
- `ProfileView` is the SAV-E Passport, not a generic settings page.

## Design Thesis

SAV-E should feel like a cream field notebook that happens to have a map inside it.

The interface language is:

```text
Memo elephant -> cream notebook -> source clue -> review candidate -> map stamp -> passport
```

Every screen should make one of those states obvious. If a user cannot tell whether
an item is a clue, a candidate, or a saved place in five seconds, the UI failed.

## Platform Boundary

Borrow Apple Maps for spatial navigation. Own SAV-E semantics for memory, source
evidence, saved state, review candidates, lists, and AI actions.

Apple Maps is the reference for map literacy, not the product identity. SAV-E can
reuse platform-native patterns such as map gestures, current-location placement,
bottom drawer mechanics, selected-place focus, and compact place information because
those reduce learning cost on iOS.

SAV-E must diverge wherever the user is deciding what a place means in their own
memory. The drawer, detail actions, social/referral surfaces, review queue, and AI
recommendations should make saved memory, unsaved candidates, source evidence,
lists, and planning actions explicit. The map shell may feel familiar; the memory
layer must feel like SAV-E.

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

A Review Clue is evidence that SAV-E has not promoted into a confirmed memory.

Rules:

- A clue is not a saved place.
- A clue can become a Review Candidate when SAV-E has a likely place match.
- A source-only clue must stay out of map-pin state unless it gains reliable
  coordinates.
- Review UI should say what is known, what is missing, and the next action.

### Passport

The Passport is the user's memory archive and control surface.

Rules:

- Use Passport for profile, language, local memory, saved count, verified count,
  cities, waiting clues, and account controls.
- Do not call it a profile unless referring to the implementation file.
- Passport should look like a notebook cover plus stamp ledger, not a settings table.

### Evidence Receipt

An Evidence Receipt shows why SAV-E believes an item is what it says it is.

Rules:

- Evidence is supporting content, not the main title.
- Source URL, caption, review count, address clue, and match status belong in an
  Evidence Receipt or compact chips.
- Do not lead a card with "Instagram Reel" when a place name exists.
- Long debug text such as pipeline names, evidence tiers, or raw diagnostics should
  stay out of primary UI.

## Vocabulary

Use these product nouns:

- SAV-E
- Memo
- Map Stamp
- Visited Map Stamp
- Review Candidate
- Source Clue
- Waiting Clue
- Memory Card
- Evidence Receipt
- Passport
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

## Color Tokens

Use current SwiftUI tokens from `Wanderly/Extensions/Color+Theme.swift`.

| Role | Token | Hex | Use |
| --- | --- | --- | --- |
| Notebook background | `saveNotebookBackground` | `#FFF5E7` | Full-screen app canvas |
| Cream surface | `saveCream` | `#FFF5E7` | Warm field notebook base |
| Notebook page | `saveNotebookPage` | `#FFF0DC` | Cards, sheets, drawer panels |
| Ink | `saveInk` | `#3A2415` | Primary text and outlines |
| Cocoa | `saveCocoa` | `#3A2415` | Dark secondary ink |
| Muted text | `saveMutedText` | `#7A5D45` | Supporting labels |
| Honey | `saveHoney` | `#FFD66B` | Primary action, Map Stamp emphasis |
| Sky | `saveSky` | `#8FCAEA` | Review, search, secondary context |
| Mint | `saveMint` | `#C8EBCF` | Confirmed, saved, success |
| Signal/coral | `saveSignal` / `saveCoral` | `#EE9C78` | Waiting, attention, review |
| Pink | `savePink` | `#F6C1CB` | Friendly accent, trip support |
| Disabled | `saveDisabled` | `#D7C0A6` | Disabled controls |

Palette rules:

- Cream is the dominant base, not yellow.
- Honey is an action/accent, not a background wash for every card.
- Mint means saved or successful.
- Sky means review/search/investigation context.
- Signal means attention, waiting, or risk.
- Ink outlines should stay visible. If a surface cannot handle a 1.4 to 2 pt ink
  stroke, the surface is probably too small or too decorative.

## Typography

SAV-E uses native system typography.

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

Source: `Wanderly/Views/Shared/MemoMascotMark.swift`.

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

Source: `Wanderly/Views/Shared/SaveMemoryBadge.swift`.

States:

- `clue`: source-only clue.
- `ready`: Review Candidate.
- `saved(category)`: Map Stamp.

Do not introduce new badge states without updating this document first.

### Map Pins

Source: `Wanderly/Views/Map/MapView.swift`.

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
2. What SAV-E extracted.
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

Source: `Wanderly/Views/Profile/ProfileView.swift`.

Required content:

- Memo identity.
- Passport name.
- Map Stamps count.
- Verified count.
- Cities count.
- Waiting clues count.
- Member since.
- Language and local memory controls.

## State Model

Every UI object must map to one of these states:

| State | Meaning | Can show on map? | Primary action |
| --- | --- | --- | --- |
| Source Clue | SAV-E preserved source evidence but lacks a confirmed place | No | Find exact place |
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
- SAV-E name prominent.
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
- Category filters live in the drawer, not as a persistent map rail.
- Current location remains bottom-right and one-handed.
- Only reliable states get pins.
- Unsaved nearby candidates are shown only after an explicit drawer action.

### Drawer

The drawer is SAV-E's command and memory workbench.

Rules:

- Collapsed drawer is the primary command bar: text input, mic input, and submit.
- The drawer may use translucent system material in map mode so the map remains the
  primary visual surface.
- Mic is push-to-talk dictation into the same command field, not a separate voice
  assistant mode.
- Required mic states: idle, requesting permission, listening, transcribed,
  loading, permission denied, unavailable, and failed.
- Filters and quick prompts belong in the drawer so the map remains clean.
- Idle drawer content should use an Apple Maps-like hierarchy: command bar, quick
  action rows, filters, recent items, and suggestions. Do not show the full agent
  command console by default.
- Separate "From your SAV-E" from "New / Unsaved".
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
