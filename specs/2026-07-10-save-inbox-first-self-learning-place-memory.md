# SAV-E Inbox-First Self-Learning Place Memory v0

Created: 2026-07-10
Source: Telegram product direction from JhiNResH + X post `saboo_shubham_/status/2074899257652597051` on self-learning agents.
Product: SAV-E
Repo: `/Users/jhinresh/projects/wanderly-current`
Status: product spec / PM Gate input
Risk: medium-high because this touches social import state, private memory, correction data, and the core SAV-E IA.

## 1. Thesis

SAV-E should not be constrained as a **map-first app**.

The map is a confirmed-memory output view. The primary product loop should be:

```text
messy place clue
→ Inbox item
→ Review Candidate with evidence
→ user confirms / edits / rejects / saves source-only
→ correction label becomes learning data
→ confirmed place becomes Map Stamp
→ Ask / Collections / Map use trusted private memory
```

SAV-E's differentiator is not “AI map pins.” It is:

```text
messy social/place signals → trusted private place memory → user-corrected learning loop
```

## 2. Product boundary

### SAV-E is

- A private place-memory agent for food, travel, and social place clues.
- A review queue for uncertain place evidence.
- A confirmed map of user-approved places.
- A learning loop that improves from user corrections.

### SAV-E is not

- A Google Maps clone.
- A public review network.
- A generic save-anything second brain.
- A social feed.
- A booking, ordering, payment, or public posting product in this slice.
- A system that auto-confirms weak social evidence as a map pin.

## 3. Why map-first is limiting

A map-first UI prematurely asks SAV-E to know exact coordinates. Most high-value inputs start messy:

```text
Instagram Reel / TikTok / XHS / screenshot / friend text / map list
→ maybe a venue name
→ maybe a city
→ maybe a creator handle
→ maybe thumbnail OCR
→ often no reliable address or branch
```

If the product opens on a map, weak candidates look like failed pins. If it opens on an inbox, weak candidates become reviewable memory work.

Product rule:

```text
Review Candidate ≠ Map Stamp
Source-only clue ≠ failed save
Map Stamp = user-confirmed or high-confidence confirmed place
```

## 4. P1 independently testable slice

Build or align the smallest product slice where a social/place capture lands in an **Inbox-first review flow** and only becomes a Map Stamp after a user decision.

### P1 user story

As a SAV-E user, when I share a messy place source, I want SAV-E to show a reviewable card with evidence and quick correction actions, so I can turn uncertain clues into trusted private place memory without polluting my map.

### P1 state machine

```text
captured
→ source_only | weak_candidate | likely_candidate | confirmed_candidate
→ user_decision: confirm | edit | reject | source_only | merge | defer
→ map_stamp only if confirm/edit creates a resolved place
→ correction_event saved for learning
```

### P1 surfaces

1. **Inbox / Needs Review**
   - Primary landing surface for new captures and uncertain candidates.
2. **Candidate Detail / Evidence Card**
   - Shows why SAV-E thinks this might be a place.
3. **Correction Actions**
   - One-tap feedback that creates labeled examples.
4. **Map**
   - Shows confirmed Map Stamps by default; optionally ghost-displays unresolved candidates only if visually distinct and non-confusing.

## 5. Information architecture

Preferred bottom navigation:

```text
Inbox | Map | Ask
```

Expanded later:

```text
Inbox | Map | Collections | Ask | Profile
```

### Inbox sections

```text
Needs Review
Recently Captured
Confirmed This Week
Source-only Clues
Suggested Collections
```

### Map sections

```text
Confirmed Map Stamps
Filtered by collection / intent / trip
Optional: show unresolved candidates only as ghost layer, off by default
```

### Ask sections

```text
Ask from my saved places
Ask from needs-review candidates
Ask from a collection or trip intent
```

## 6. Candidate card contract

Every Inbox card should make uncertainty understandable.

Minimum card fields:

```text
id
source_type: instagram | tiktok | xhs | google_maps | apple_maps | screenshot | friend_text | url | manual
source_url / source_ref
canonical_source_url
source_preview: title / thumbnail / excerpt
candidate_title
candidate_address
candidate_city
candidate_country
candidate_place_id / maps_url if available
confidence: 0.0-1.0
evidence_tier: confirmed | likely | weak_candidate | source_only
missing_fields[]
evidence_refs[]
suggested_collection_ids[]
suggested_reason
status: captured | needs_review | confirmed | rejected | source_only | merged | deferred
created_at
updated_at
```

### Evidence refs

Evidence should be explicit and user-visible when useful:

```text
evidence_refs[]:
  - type: caption | structured_location | creator_handle | thumbnail_ocr | frame_ocr | places_match | user_note | friend_message | map_link
  - value / snippet
  - confidence
  - source_offset or frame_time if available
  - privacy: private | safe_summary
```

## 7. Correction actions

User correction is the learning loop. Do not hide it behind an edit screen only.

### Required quick actions

```text
Confirm
Edit place
Not this place
Wrong city / branch
Save source only
Merge with existing place
Add why I wanted this
Move to collection
Reject / hide
Ask SAV-E to investigate more
```

### Correction event schema

Every correction should create a durable event.

```text
correction_events:
  id
  user_id
  capture_id
  candidate_id nullable
  event_type:
    confirm_candidate
    edit_place_identity
    edit_address
    wrong_place
    wrong_city
    wrong_branch
    save_source_only
    merge_existing
    add_reason
    change_collection
    reject_candidate
    investigate_more
  before_snapshot json
  after_snapshot json
  source_evidence_tier_before
  confidence_before
  user_final_place_id nullable
  user_final_collection_ids[]
  user_reason_text nullable
  created_at
```

## 8. What SAV-E learns without fine-tuning

Do not start with model fine-tuning. Start with context, memory, heuristics, and retrieval.

| User behavior | Learning target | First implementation |
|---|---|---|
| Corrects place name | Entity matching | Store correction pair and prefer corrected entity for similar source/handle/caption patterns |
| Corrects city/branch | Disambiguation | Boost same-city/branch constraints for this user and source pattern |
| Rejects candidate | False positive pattern | Lower confidence for matching evidence pattern |
| Saves source only | Confidence threshold | Avoid forcing place creation when evidence is weak |
| Adds “why I wanted this” | Preference memory | Use reason in Ask / ranking / collection suggestions |
| Changes collection | Personal taxonomy | Suggest similar collection for future captures |
| Confirms weak candidate | Evidence threshold | Store which weak signals are acceptable for this user |
| Merges with existing place | Deduplication | Improve future duplicate detection |

## 9. Ranking / evidence rules

Default evidence ladder:

```text
confirmed:
  structured map/place link OR user confirmation OR official/Places match with high confidence

likely:
  venue name + city/address clue OR social handle + external place match

weak_candidate:
  caption/thumbnail/handle suggests a place but address/branch missing

source_only:
  source is saved but SAV-E cannot name a reliable place
```

Hard rules:

- Weak social evidence stays out of confirmed map state.
- Source-only items remain useful in Inbox/search; they are not failed saves.
- `(0,0)`, San Francisco fallback, or placeholder coordinates must never appear as confirmed visible places.
- User confirmation can promote a weak candidate, but the source evidence tier should still remain visible for audit.

## 10. Acceptance scenarios

### Scenario A — weak Instagram Reel

Given a Reel has no structured location but includes a creator handle and thumbnail OCR clue,
When the user shares it to SAV-E,
Then SAV-E creates a Needs Review card with `evidence_tier = weak_candidate` or `source_only`,
And the Map does not show a confirmed pin,
And the user can confirm, edit, save source-only, or reject.

### Scenario B — Google Maps link

Given the user shares a Google Maps place link,
When SAV-E resolves the link to a place identity,
Then it may create a high-confidence candidate,
And still asks for confirmation if this is the first time or if collection/reason is unknown,
And only confirmed items become Map Stamps.

### Scenario C — user fixes wrong branch

Given SAV-E suggests the wrong branch of a restaurant,
When the user taps “Wrong branch” and selects/edits the right place,
Then SAV-E stores a correction event with before/after snapshots,
And the final place can become a Map Stamp,
And future similar captures prefer the corrected branch/city pattern.

### Scenario D — source-only is useful

Given SAV-E cannot identify a place,
When the user chooses “Save source only,”
Then the source appears in Inbox/Search as source-only memory,
And it does not pollute the map,
And Ask SAV-E can later surface it as “unresolved clue.”

### Scenario E — Ask uses private memory

Given the user has confirmed places and correction events with reasons/collections,
When the user asks “找一個適合 casual date、不想排隊太久的地方,”
Then Ask SAV-E ranks from confirmed Map Stamps and private claims/reasons first,
And cites whether the recommendation came from confirmed memory, likely candidate, or source-only clue.

## 11. UI/UX requirements

### Inbox card

Must show:

- Source preview.
- Candidate title or “source saved, place unknown.”
- Evidence tier badge.
- Missing fields.
- Primary action: Confirm or Review.
- Secondary actions: Edit, Not this, Source only.

### Candidate detail

Must show:

```text
Why SAV-E thinks this:
- caption / thumbnail / handle / Places / user note evidence
What is missing:
- address / branch / exact venue / city
Decision:
- confirm / edit / reject / source-only / investigate
```

### Map

Default map filter:

```text
Confirmed only
```

If unresolved candidates are shown, they must be visually distinct:

```text
ghost pin / dotted outline / “Needs review” badge
```

No unresolved candidate should look equivalent to a confirmed saved place.

## 12. Data / privacy requirements

- All captures, candidates, corrections, reasons, and collections are user-owned/private by default.
- Raw friend messages, screenshots, receipts, and private notes must not appear in public/shared surfaces.
- Public-safe summaries must be separated from raw private evidence.
- Correction events may be used for per-user product learning, but should not be globally aggregated without explicit design review.
- No public feed, social graph, review wall, or public claim card in this slice.

## 13. Instrumentation

Minimum events:

```text
capture_created
candidate_created
candidate_review_opened
candidate_confirmed
candidate_edited
candidate_rejected
candidate_source_only_saved
candidate_merged
correction_event_created
map_stamp_created
ask_used_candidate
ask_used_confirmed_place
```

Minimum metrics:

```text
capture_to_candidate_rate
candidate_to_confirmed_rate
source_only_rate
false_positive_rejection_rate
wrong_branch_rate
time_to_confirm
places_pollution_rate: unresolved items appearing as confirmed pins (must be 0)
ask_uses_private_memory_rate
```

## 14. Customer-value eval

Before calling this successful, test with at least 10 real founder/friend captures.

Target eval set:

1. Instagram/TikTok Reel with one weak venue clue.
2. Reel with only creator handle.
3. Screenshot with visible venue name but no address.
4. Friend text like “next time try this Bangkok place.”
5. Google Maps link.
6. Multi-place caption/list.
7. Wrong branch suggestion.
8. Source-only URL that still matters later.
9. User adds “why I wanted this.”
10. Ask SAV-E query that should use confirmed memory and reasons.

Pass threshold:

```text
- 0 weak/social items become confirmed map pins without user decision.
- ≥7/10 captures preserve useful memory even when not confirmed.
- ≥5/10 produce a candidate or source-only item the user understands.
- ≥3 user corrections are captured as structured correction_events.
- At least one Ask answer uses a user-added reason or correction event.
```

## 15. Out of scope for v0

- Public reviews, likes, comments, or feeds.
- Public claim-card publishing.
- Payments, booking, reservations, or on-chain receipts.
- Global model fine-tuning.
- Logged-in scraping of social platforms.
- Fully automatic video download/OCR unless already available in existing pipeline.
- Broad redesign of every app surface.
- Replacing the map; the map remains the confirmed-memory view.

## 16. Engineering handoff notes

This spec should extend, not replace:

- `specs/save-memory-layer.md`
- `specs/save-search-reviews-receipts-v0.md`
- `specs/social-handle-review-candidates.md`
- `specs/source-only-search-recovery-plan.md`
- `specs/2026-07-08-save-claim-cards-v0.md` if present in this repo checkout

Expected implementation sequence:

```text
1. Inspect existing capture/candidate/review/map data model.
2. Identify current home/map/default app entrypoint.
3. Add or align candidate status/evidence tier fields if missing.
4. Add correction_events persistence or local-first equivalent.
5. Add Inbox / Needs Review surface or adapt existing review queue.
6. Ensure Map filters confirmed Map Stamps only.
7. Add tests/smoke checks for weak candidate not becoming confirmed map pin.
8. Add instrumentation events for correction loop.
```

## 17. Verification commands / checks

Exact commands must be confirmed from repo before implementation. Minimum verification should include:

```text
- Existing TypeScript / backend checks if backend schema/API changes.
- Existing iOS/Xcode build or Swift test route if native UI changes.
- Focused social import tests if parser/import logic changes.
- Manual smoke: share weak social source → Inbox candidate/source-only → confirm/edit/reject → Map confirmed only.
```

If no test exists for this path, Engineering Worker should add the smallest regression fixture before changing behavior.

## 18. Decision frame

Decision: make SAV-E **Inbox-first for messy place memory**, Map-confirmed for trusted output.

Options considered:

1. Keep map-first and add better pins.
2. Add an Inbox / Review Queue before map confirmation.
3. Pivot to generic agent memory / second brain.

Chosen tradeoff:

```text
Use Inbox-first + confirmed Map. This protects trust, turns uncertainty into product value, and creates labeled learning data from user corrections.
```

Rejected alternatives:

- Map-first only: too much pressure to create fake/weak pins.
- Generic second brain: loses SAV-E's place-specific wedge.
- Public review network: cold-start/moderation heavy and misaligned with private memory.

Expected outcome:

```text
More captures remain useful, fewer bad pins pollute the map, and every correction compounds SAV-E's private memory layer.
```

## 19. Open questions

These should not block the v0 spec, but should be answered before broad implementation:

1. Should Inbox become the default launch tab for all users or only users with pending review items?
2. Should source-only items appear in Ask by default or only when the user asks for unresolved clues?
3. Should correction_events live in backend first, local vault first, or both?
4. What is the minimum UI needed to show evidence without overwhelming consumer users?
5. What exact term should ship in UI: “Review Candidate,” “Place Clue,” “Needs Review,” or something softer?

## 20. Product copy direction

Avoid:

```text
AI map for saved places
```

Use:

```text
Stop losing places you wanted to try.
```

or:

```text
SAV-E turns messy place clues into trusted private place memory.
```

Flow copy:

```text
Capture the clue.
Review what SAV-E found.
Stamp your map only when it's right.
```
