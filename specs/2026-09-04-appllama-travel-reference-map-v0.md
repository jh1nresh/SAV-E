# AppLlama Travel Reference Map v0

Status: research / clarification brief. No product UI change in this ticket.
Date: 2026-09-04
Source: [AppLlama](https://appllama.io/) homepage feature **Parkwolf: National Park Guide**, plus closer Travel analogs **Mapstr** and **park4night**.

AppLlama is a screen library of top-earning iOS apps. It is a reference, not a
token source. `DESIGN.md` and `Color+Theme.swift` still win.

Visual studies (proposal only, not production UI):

- [Want to try Memory Card](../design-assets/appllama-studies/memory-card-want-to-try.png)
- [Visited Memory Card](../design-assets/appllama-studies/memory-card-visited.png)
- [Map drawer intent filters](../design-assets/appllama-studies/map-drawer-intent-filters.png)

## Required brief

- Paid user job / observed failure: paid users need a private map of confirmed
  places they can plan around. AppLlama's current Travel feature (Parkwolf)
  looks like a nearby analog, but copying it blindly would turn Savvy into a
  public park-guide / audio-tour / paywall product.
- Acceptance criteria: this spec names which AppLlama flows may inform which
  Savvy surfaces, which must not be copied, and which existing files already
  own that job. A later UI PR can implement one slice without re-litigating
  product boundary.
- Failure fixture: a follow-up diff that adds a marketing onboarding carousel,
  a launch paywall, a UGC sightings feed, wildlife heatmaps, GPS audio tours,
  or XP/quest chrome "because Parkwolf does it."
- Classification: research / loop (design-reference mapping). Not a feature
  implementation.
- Demand proof: founder asked to study https://appllama.io/ and map what can
  enter the app. Parkwolf is AppLlama's current Travel showcase (~$60K/mo,
  77 screens, 12 flows). Closer product analogs on the same site are Mapstr
  (save & follow places) and park4night (map browse + around-a-place).
- Pricing / paywall hypothesis: unchanged from
  `specs/2026-09-04-launch-purchase-path-trigger-later-v0.md` — free download,
  purchase path ready, trigger later. No launch/onboarding wall. Parkwolf /
  Mapstr / park4night paywalls are later Pro-study material only, not v1 UI.
- First distribution format: this spec + PR. No TestFlight, store, or
  screenshot change.
- Files and systems in scope: this spec only. Implementation files named below
  are the landing spots for a later slice, not this ticket.
- Verification commands: `git diff --check`. No Xcode, simulator, or CI gate.
- Security and privacy boundary: do not import AppLlama assets, screenshots,
  or user-generated park content into the app bundle. Do not add analytics,
  UGC feeds, or community sightings.
- Human approval still required: which P0 slice to implement next; any DESIGN
  amendment; merge; later paywall / Pro work.

## What AppLlama is, and how to use it here

Browse path that stays inside Savvy's job:

```text
AppLlama → Travel
  1. Mapstr – Save & Follow Places   (closest product analog)
  2. park4night                      (map literacy + around-a-place)
  3. Parkwolf                        (homepage feature; borrow map/place/saved,
                                      not audio/wildlife/paywall)
```

Useful AppLlama indexes, without copying conversion chrome:

- Flows: Place Details, Map Browsing, Saved & Planning, Around a Place, Search
- Elements: Chips & Pills, Sheets, Search, Cards, Progress Indicators
- Skip for v1: Paywall, Streak Calendar, Challenges, Community Feed

AppLlama Pro also ships an MCP at `https://mcp.appllama.io/mcp`. Do not add it
until a human enables that subscription. Mobbin was unavailable in this pass.

Token authority does not change. AppLlama may suggest interaction density and
flow shape. It may not introduce new product nouns, palette values, or states.

## Product boundary

Savvy job:

```text
messy clue → Review Candidate → Map Stamp → Plan around this
```

Parkwolf job:

```text
pick a park → download offline pack → audio tour + wildlife map → pin favorites
```

Mapstr job:

```text
save a place → tag / To try vs Done → personal map → follow friends' maps
```

park4night job:

```text
land on map → filter spots → read photos + amenities → save / plan around
```

Savvy may borrow map literacy and place-object density. It must keep:

- clue / candidate / Map Stamp as three visible states
- private memory, no public UGC feed
- proof-first onboarding, not a feature carousel
- no launch paywall
- Passport Collection as a stamp ledger, not XP

## Parkwolf's 12 flows → Savvy landing spots

Parkwolf screens on AppLlama: Onboarding, Paywall, Audio Guide Exploration,
Park Exploration, Park Media Gallery, Place Exploration, Places Browse,
Trail Exploration, Wildlife Explorer, Sightings, Account, Saved & Planning.

| Parkwolf flow | Savvy landing | Borrow | Do not copy |
| --- | --- | --- | --- |
| Onboarding | `OnboardingView.swift` | After the first Map Stamp, one optional "where are you collecting places?" city/area prompt is allowed. Mapstr's 15-step tooltip tour is a negative example. | 6-step marketing carousel (audio, offline, wildlife, favorites, park picker). `DESIGN.md` onboarding is Language → Clue → Candidate → Map Stamp. |
| Paywall | `SaveProPaywallView.swift` (hidden until Passport / AI-refusal trigger) | Later Pro study: social proof + annual trial vs monthly. Passive Passport entry after one Map Stamp; reactive wall only after AI refusal once enforcement is on. | Any paywall in the first-run, onboarding, or save path. See `2026-09-04-launch-purchase-path-trigger-later-v0.md`. |
| Audio Guide Exploration | none | — | GPS audio tour, CarPlay guide, Memo-as-narrator. Memo stays a memory keeper. |
| Park Exploration | `MapView.swift`, `SaveMapDrawerPanel.swift`, drawer `categoryFilterStrip` | Layered map literacy. Bottom search shelf. Amenity-style chips in the drawer, not a persistent map rail. | Official park overlay packs, restroom/gas as new product types, download-a-park gate. |
| Park Media Gallery | `PlaceBusinessPhotoCarousel` in `AIDrawerView.swift` | Swipeable photos on the Memory Card. Photo + map peek in one object. | Public activity/photo feed. |
| Place Exploration | `AIDrawerView` saved-place drawer, `PlaceBottomSheet.swift` | Identity → photos → kraft chips → one coral primary → overflow. Parkwolf pin-favorite ≈ Add to Trip / Plan around this. | Landmark encyclopedia pages, trail stats as the hero. |
| Places Browse | `SaveLibraryView` (pushed Saves route, not a root tab) | List of confirmed Map Stamps vs waiting clues. Filter by category and Want to try / Visited. | A generic "all parks" catalog. |
| Trail Exploration | `TripPackViews.swift`, `TripItineraryComponent.swift` | Ordered stops, distance/time as supporting facts. | Hiking trail product, elevation profiles, offline trail packs. |
| Wildlife Explorer | none | — | Heatmaps, species layers, notification-for-bears. |
| Sightings | none | Evidence Receipt already shows *why this place*. | Community UGC sightings feed. Launch notes: no UGC feed. |
| Account | `ProfileView.swift` Passport Collection | Stamp-ledger density. Cities strip already exists. | "My Park Tracker" mosaic as a reward board, XP, login streak calendar. Forbidden by DESIGN and `specs/2026-09-04-save-passport-field-streak-collection-v0.md`. |
| Saved & Planning | Pushed Saves route + Trips tab + `Plan around this` | Split **saved memory** from **route**. This is the closest Parkwolf overlap. | Bundling Saves and Trips into one "favorites" list. |

## Closer analogs on the same site

### Mapstr — first AppLlama Travel app to reopen

Closest paid-job match: a personal map of saved restaurants, stays, and spots.

Borrow into Savvy:

- **To try vs Done** → existing `Place.status` `.wantToGo` / `.visited`. Make
  that state visible on the Memory Card, not only in `memorySummary` copy.
- **Tags** → `PlaceCollection` already exists on `UserProfile`. Do not invent a
  new taxonomy. Later slice: add a confirmed Map Stamp to a collection from
  the drawer.
- **Google Maps import** → `GoogleTakeoutImportView.swift`. Parkwolf's granular
  offline-download checklist is the progress-UI reference for a long Takeout
  parse, not a new offline-park product.
- **Street view binoculars** → hand off to Apple Maps. Do not embed Street View.

Do not copy:

- 15-step onboarding before the map
- soft paywall after profile setup
- public follow-the-creator maps as the default
- batch-edit as a launch requirement

### park4night — map literacy reference

Borrow into Savvy:

- **Land on the map in seconds.** Savvy already has a Map tab and an Apple
  Maps–style collapsed search shelf. Keep that. Do not hide the map behind a
  catalog.
- **Login only when the action needs it.** Sample-clue onboarding already
  follows this. Do not add a login-required modal on browse.
- **Around a Place** → already shipped as **Plan around this**. The gap is
  discoverability on the saved-place drawer, not a new planner.
- **Filters live with search**, not as a permanent map chrome. Matches
  `DESIGN.md` drawer rules. Current chips are `PlaceCategory` pills in
  `AIDrawerView.categoryFilterStrip`.

Do not copy:

- paywall on "save to favorites"
- community reviews as the place's primary identity
- vehicle-height / campsite amenity matrices

## Ranked slices that may enter the app later

These are the only places a follow-up PR should land. One slice per PR.

### P0 — Place drawer: Want to try / Visited as a visible state

- Observed gap: `Place.memorySummary` already says "Saved as a place to try"
  vs "Marked visited", but the saved-place drawer leads with Add to Trip and
  does not give Want to try / Visited a badge-level state.
- AppLlama reference: Mapstr To try / Done; Parkwolf Place Exploration pin
  state.
- Landing files: `SAV-E/Views/Drawer/AIDrawerView.swift` (saved-place drawer),
  `SaveMemoryBadge.swift` only if DESIGN is amended. Prefer a kraft chip or
  existing mint/coral ticket style before a new badge enum.
- Keep the five-second test: this is a Map Stamp substate, not a fourth
  primary state.

### P0 — Place drawer: Plan around this next to Add to Trip

- Observed gap: Add to Trip is the coral primary. Plan around this exists in
  search/intent models (`SaveSearchModels.planAround`) but is easy to miss
  on the Memory Card.
- AppLlama reference: park4night Around a Place; Parkwolf Saved & Planning.
- Landing files: `AIDrawerView.swift` saved-place actions, copy already in
  `SaveSearchModels.swift`.
- One coral primary. Plan around this is the secondary paper button, not a
  second coral CTA.

### P1 — Drawer chips: Want to try / Visited / Nearby, not new amenity types

- Observed gap: filters are category-only (`food`, `cafe`, `bar`,
  `attraction`, `stay`, `shopping`).
- AppLlama reference: Parkwolf restroom / food / gas chips; park4night type
  filters. Translate to Savvy nouns, not park amenities.
- Landing files: `AIDrawerView.swift` `categoryFilterStrip`, `MapViewModel`
  selected categories.
- Do not add restrooms, gas, wildlife, or trails as `PlaceCategory` values.

### P1 — Takeout import progress as a checklist

- Observed gap: `GoogleTakeoutImportView` has parse/save states but not
  Parkwolf-style granular "what is being saved" feedback.
- AppLlama reference: Parkwolf Yosemite offline-download checklist.
- Landing files: `GoogleTakeoutImportView.swift`,
  `GoogleTakeoutImportService.swift`.
- This is import progress, not an offline map pack.

### P2 — Memory Card photo gallery density

- Already present: `PlaceBusinessPhotoCarousel` when more than one business
  photo exists.
- AppLlama reference: Parkwolf Park Media Gallery; park4night spot photos.
- Follow-up only if a confirmed Map Stamp with several photos still shows a
  single thumbnail. Do not add a public gallery tab.

### P2 — Passport Collection visual density

- Already present: Collection rows for Map Stamps, Visited, Cities, Waiting
  clues (`ProfileView.PassportStampSection`).
- AppLlama reference: Parkwolf My Park Tracker mosaic.
- Allowed: denser city/stamp ledger on Atlas paper.
- Forbidden: mosaic-as-rewards, XP, quest board, login calendar.

## Explicitly out of the app

Do not file implementation tickets for:

- Parkwolf / Mapstr / park4night paywalls in first-run or save
- GPS audio tours, CarPlay guides, wildlife heatmaps, sightings feeds
- Feature-carousel onboarding
- Community activity feeds or public creator maps
- Offline national-park data packs
- New PlaceCategory values copied from park amenities
- Embedding Google Street View
- AppLlama screenshot assets in `design-assets/` or the iOS bundle

## Verification for this ticket

```bash
git diff --check
```

No simulator. No `xcodebuild`. A later UI slice uses the ordinary unsigned
generic iOS Simulator compile from `AGENTS.md`.

## Human decisions still open

1. Which P0 slice to implement first: visible Want to try / Visited, or Plan
   around this on the Memory Card.
2. Whether Want to try / Visited becomes a `SaveMemoryBadge` substate (needs a
   DESIGN amendment) or stays a kraft chip on an existing Map Stamp.
3. AppLlama Pro MCP is optional tooling, not a product dependency.
