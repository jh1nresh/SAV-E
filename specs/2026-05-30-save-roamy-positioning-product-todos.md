# SAV-E Roamy-Informed Positioning and Product TODOs

## Source

- `/Users/jhinresh/brain/qa/2026-05-30-save-positioning-and-better-app-strategy.md`
- `/Users/jhinresh/brain/qa/2026-05-30-save-roamy-competitor-positioning.md`

## Decision

SAV-E should be positioned as a **private place memory app**, not an AI travel planner, Google Maps replacement, Yelp replacement, or generic save-anything vault.

Working line:

```text
SAV-E turns the restaurants, cafes, attractions, and travel spots you saved everywhere into your private map memory.
```

Core thesis:

```text
SAV-E captures intent at discovery time and activates it at decision time.
```

Examples:

- Today: a friend sends a restaurant, or the user sees it on IG/TikTok/Xiaohongshu -> SAV-E saves the source as a clue/candidate.
- Two weeks later: date night nearby -> SAV-E wakes up trusted saved places first.
- Next month: Tokyo trip -> SAV-E turns confirmed place memory into a plan.

Short App Store hook:

```text
Stop losing places you already wanted to try.
```

## Competitor Takeaway

Roamy validates the saved-social-places wedge:

```text
saved Instagram/TikTok spots -> map -> trip plan
```

SAV-E should not copy Roamy as another AI itinerary generator. The better product wedge is:

```text
messy place signal -> Source Clue -> Review Candidate -> confirmed Map Stamp -> Ask/Plan from trusted saved places
```

The opening is trust and control:

- no fake confirmed pins;
- no unlabeled AI itinerary claims;
- source evidence stays visible;
- uncertain places stay in Review;
- public recommendations are clearly separated from `From your SAV-E`.

## Product Rules

### Memory First, Discovery Second

Default answer from my memory first; public discovery second and clearly labeled.

SAV-E should not begin by asking:

```text
What kind of traveler are you?
```

It should begin from the user's real data:

- saved places;
- friend-shared places;
- Google Maps saved lists;
- IG/TikTok/Xiaohongshu links;
- tried places and private review history.

### Every Saved Place Carries Context

Every saved place should carry source, state, tags/reasons, and next-best action.

Each Map Stamp should eventually know:

- why it was saved;
- who shared it;
- original source;
- confirmation state;
- suitable context;
- tried/untried state;
- private review;
- whether it is relevant nearby right now.

### Map Is A Work View

Map is not the entire app identity. The main product identity is private place memory.

Map states must remain distinct:

- confirmed Map Stamp;
- Review Candidate;
- Source-only clue;
- unsaved public map result.

### Drawer Gives Next Action

The drawer is the agent/action surface, not a generic chat tab.

- Source-only clue -> Find exact place.
- Review Candidate -> Confirm / edit / reject.
- Unsaved map result -> Save as Map Stamp.
- Saved place -> Plan around this / add note / mark tried.
- Decision query -> answer from saved places first.

## Product Boundary

In scope for the SAV-E consumer app now:

- restaurants, cafes, bars, attractions, hotels, cities, trips;
- Google Maps saved lists;
- Instagram/TikTok/Xiaohongshu/social place signals;
- friend-shared places and pasted links;
- Source Clue, Review Candidate, and Map Stamp state;
- Ask saved places for nearby food, date night, trip days, and food crawls;
- plan from confirmed or clearly labeled candidate memory.

Out of scope for this phase:

- recipes, shopping, notes, todos, generic links;
- public social feed;
- booking/payment/POS actions;
- generic "AI travel agent" positioning;
- Roamy-style hard-paywall trust damage before users see value.

## App Store Copy Direction

Title direction:

```text
SAV-E: Private Place Map
```

Subtitle options:

```text
Private place memory
Save places from Reels
Ask your saved places
```

Short description:

```text
Save messy restaurant and travel clues, review uncertain places, and ask your private map where to go next.
```

Do not lead with:

- `AI travel planner`;
- `Google Maps replacement`;
- `Yelp replacement`;
- `discover hidden gems`;
- `save anything`.

## Screenshot Story

1. `Stop losing places friends send you.`
   - Show a messy Reel/link/list becoming a reviewable SAV-E place clue.
2. `Bring lists into your own place memory.`
   - Show Google Maps/social list import as reviewable memory, not blind auto-save.
3. `Ask your saved places first.`
   - Show nearby/date/trip query answered from confirmed Map Stamps first.
4. `Know what is confirmed.`
   - Show Source Clue / Review Candidate / Map Stamp states.
5. `Plan from places you already wanted.`
   - Show generated plan with saved vs new recommendations labeled.

## Repo Implementation TODOs

### P0 - First-Run Positioning

- Replace generic vault or itinerary wording with private place memory wording.
- First screen should answer: "I saved this somewhere. Can SAV-E help me use it when I need a decision?"
- Show one real capture path: Share Sheet / paste link / Google Maps list.
- CTA should be `Add Spots` / `Save a Place`, not a vague AI prompt.
- Show the sequence in 20 seconds: import a place already saved elsewhere -> Review Candidate -> confirmed Map Stamp -> ask SAV-E to plan around saved places.

Acceptance:

- No first-run copy says SAV-E is a generic vault.
- No first-run copy implies confirmed coordinates without review.
- User can understand Source Clue -> Review Candidate -> Map Stamp in one screen.

### P0 - Review-State Trust Layer

- Keep Source Clue, Review Candidate, Map Stamp labels visible in import/review flows.
- A weak social caption cannot become a confirmed Map Stamp without address/Places/user confirmation.
- Source links must be clickable from review detail.

Acceptance:

- Import failures preserve source-only clues with next-best action.
- Candidate title/address can be edited before save.
- Confirm action is disabled or redirected when evidence is not strong enough.

### P0 - Ask Saved Places First

- Nearby/date/trip queries should retrieve saved/review candidates deterministically before LLM narration.
- Split results into `From your SAV-E`, `Review candidates`, and `Public discovery`.
- LLM may explain or summarize, but cannot create place identity, category, coordinates, or confirmation state.

Acceptance:

- "nearby coffee" and "nearby restaurant" return saved-first sections when available.
- Public fallback is labeled as public discovery and never mixed into `From your SAV-E`.
- Wrong category and wrong location cannot satisfy a category/location ask.

### P1 - Roamy-Parity Capture

- Harden Instagram/TikTok public metadata + OCR recovery.
- Keep Google Maps saved-list import as a first-class path.
- Add content-test fixtures for hard social posts: single venue, listicle, address-only, source-only.

Acceptance:

- SocialPlacePipelineTests cover each source state.
- Every parser PR includes a fixture or regression case.
- No parser path invents address/coordinates.

### P1 - Plan From Memory

- Generated plans should label saved places, pending candidates, and new suggestions separately.
- A plan can start from a user anchor: saved place, map area, current location, or imported list.

Acceptance:

- Plan artifact shows why each stop was included.
- Saved places outrank public recommendations.
- User can swap/remove generated stops.

### P2 - Monetization and Distribution

- Test content hook before paywall optimization.
- Suggested hook: `30 days, 100 messy food/travel posts. Can SAV-E turn them into trustworthy private map memory?`
- Pro can later gate high-volume imports, social parsing, vault chat, and advanced planning.

Acceptance:

- Do not ship a hard paywall before the core place-memory aha works.
- Trial/pricing copy must be explicit and non-surprising.

## Metrics

- Source Clue -> Review Candidate conversion.
- Review Candidate -> Map Stamp confirmation rate.
- Confirmed Map Stamp count per active user.
- Ask query success rate from saved places.
- Share/paste/import completion rate.
- Parser false-positive rate: wrong title, wrong address, fake pin.

## Immediate Next PRs

1. First-run copy and Add Spots CTA alignment.
2. Review detail editability and clickable source link audit.
3. Ask SAV-E saved-first answer copy and section labels.
4. App Store screenshot board refresh with private place memory copy.
5. Parser fixture backlog for hard IG/TikTok/Xiaohongshu cases.
