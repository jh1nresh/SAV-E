# SAV-E MVP Scope: Save, Search, Recommend, Share Places

> Created: 2026-06-11
> Product: SAV-E / Wanderly
> Status: MVP scope decision
> Decision: AI itinerary planning is out of the first MVP loop.

## One-line decision

SAV-E MVP should focus on:

```text
capture messy place signal
→ review candidate
→ save Map Stamp
→ search / ask / recommend from saved places
→ open or share the place memory
```

Do not make AI itinerary planning a core MVP promise yet.

## Why

The first user pain is not:

```text
I have a clean database of places; please optimize my itinerary.
```

The first user pain is:

```text
Friends, IG, TikTok, Xiaohongshu, Google Maps, screenshots, and chat messages contain places I want to remember, but I lose them before I can use them.
```

So the MVP must prove SAV-E can become the user's private place memory before it tries to become a trip-planning agent.

## MVP core loop

```text
1. User shares / pastes / imports a place clue.
2. SAV-E turns it into a reviewable candidate.
3. User confirms or edits it.
4. SAV-E saves it as a Map Stamp.
5. User can search, ask, open in maps, or share it later.
```

## MVP surfaces to keep

### 1. Saved places search

Users can quickly search existing saved places.

Examples:

```text
Omomo
Rise Bagels
Irvine coffee
that bagel place
```

Expected behavior:

```text
search saved Map Stamps first
→ show matching results
→ highlight pins
→ open result detail
```

### 2. Ask / recommend from saved places

Users can ask lightweight intent questions over saved memory.

Examples:

```text
我今天想喝奶茶
coffee near UCI
適合約會的餐廳
something sweet after dinner
```

Expected behavior:

```text
parse intent
→ search saved places first
→ rank likely matches
→ explain why
→ no hallucinated places
```

If no saved place matches:

```text
No saved milk-tea memories yet. Want SAV-E to look nearby?
```

Public lookup is optional and clearly labeled unsaved.

### 3. Import / share / clipboard

Keep low-friction capture:

- Share Extension
- clipboard URL import
- pasted notes
- Google Maps link/import where available
- social/video link as review candidate
- screenshot/media evidence as review candidate if implemented

The UX goal is:

```text
I saw/saved/received a place somewhere else → SAV-E can catch it.
```

### 4. Review candidate

Imported or extracted place clues should not auto-save when evidence is weak.

Candidate state should show:

- likely place name
- source / evidence
- confidence
- missing info
- address / coordinates if reliable
- primary action: `Save` / `Review` / `Find exact place`

### 5. Map Stamp

Confirmed places become private SAV-E memory.

Map Stamp must be clearly distinct from:

- public map candidate
- source-only clue
- review candidate

### 6. Simple open in maps

Saved place detail should include a simple action:

```text
Open in Apple Maps / Google Maps
```

Do not overbuild routing or itinerary optimization in MVP.

### 7. Share a saved place / collection

Sharing is part of the acquisition loop.

MVP sharing can be simple:

- share one saved place card
- share a small collection/list
- include source/evidence if safe
- recipient can open a web/app preview later

The growth loop is:

```text
save place
→ share place card / collection
→ friend opens preview
→ friend saves/imports it into their SAV-E
```

### 8. Lightweight suggest from saved places

Allowed as a later MVP polish, not full itinerary planning.

Examples:

```text
Suggest one boba place
Pick a dinner spot from my saved places
Show date-night candidates
```

Output should be a ranked shortlist, not a multi-day plan.

## Explicitly out of MVP

Remove or downgrade these from the first MVP promise:

- full AI itinerary planning
- multi-day trip planning
- route optimization
- Trip Canvas as core CTA
- `Plan LA 2 days` as a primary drawer suggestion
- public discovery as default behavior
- reservations / ordering / payments
- automatic saving of public candidates

These can return later after the place-memory loop works.

## Drawer UX direction

The drawer should feel like one assistant input, but the MVP capabilities should be narrower:

```text
Save or find a place...
```

or:

```text
Ask SAV-E about your saved places...
```

Better first-run chips:

```text
Paste a link
Search saved places
Find boba
Review clues
Open my map
Share a place
```

Avoid primary chips like:

```text
Plan a 2-day itinerary
Build full trip
Optimize route
```

## MVP result sections

Use these result sections before adding planning sections:

```text
From your SAV-E
Review candidates
Nearby unsaved candidates
No saved match
```

Do not show `Planning answer` as a primary MVP section.

## AI usage in MVP

AI should help with place memory, not trip planning.

Good AI use:

```text
extract likely place from messy input
summarize evidence
identify missing info
classify category
rank saved places for an intent
explain why a saved place matches
```

Bad MVP AI use:

```text
invent full itinerary
recommend places not in memory without labeling them public/unsaved
pretend weak candidates are confirmed places
```

## Acceptance criteria

The MVP is working when:

1. A user can share/paste/import a place clue.
2. SAV-E creates a review candidate instead of losing it.
3. The user can save it as a Map Stamp.
4. The user can search it later by name, category, or fuzzy intent.
5. The user can ask for simple recommendations from saved places.
6. The user can open the saved place in maps.
7. The user can share one saved place or a small collection.
8. No public/AI-generated candidate is confused with confirmed saved memory.

## Future layer

AI planning should return after the above loop is reliable.

Future sequence:

```text
saved place memory works
→ search/recommend feels good
→ sharing creates acquisition loop
→ users accumulate enough places
→ lightweight plans from saved memory
→ full itinerary / Trip Canvas
```
