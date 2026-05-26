# Agent-native SAV-E Cards V0

> Created: 2026-05-19
> Status: proposed implementation slice

## Product decision

SAV-E should stop being framed primarily as a destination app. The current app can remain a useful debug/import surface, but V0 should prove the agent-native primitive:

```text
messy place signal -> private local memory -> structured SAV-E Card -> agent/human share/import
```

This makes SAV-E closer to an agent-readable place memory standard than a Yelp/Maps clone.

## Current repo evidence

The repo already has most raw pieces:

- Native local vault:
  - `Wanderly/Models/SaveMemoryRecord.swift`
  - `Wanderly/Services/SaveLocalVaultService.swift`
  - `Wanderly/Intents/SavePlaceFromURLIntent.swift`
  - `Wanderly/Intents/AskSaveMemoryIntent.swift`
  - `Wanderly/Views/Profile/SaveMemoryDebugView.swift`
- Social/link candidate parser:
  - `Wanderly/Services/SocialLinkReviewCandidateService.swift`
  - `Wanderly/Services/PendingPlaceImportService.swift`
- Backend memory trail:
  - `backend/sql/schema.sql`: `captures`, `place_candidates`, `agent_decisions`, `recommendation_sets`, `recommendation_items`, `agent_tool_calls`
  - `backend/src/server.ts`: `/memory/*` and `/agents/*` routes
- Share surfaces:
  - `WanderlyClip/ClipContentView.swift` currently previews `wanderly.app/trip?d=<base64>`
  - `save-rn/src/sharedTrip.ts` builds/decodes base64 trip links
  - `save-rn/App.tsx` already has import, trip selection, and share tab

Missing piece: there is no first-class `SAV-E Card` schema/render/import contract. Existing sharing is trip-link specific and app-shaped.

## V0 thesis

For our own dogfood, do **not** start with a big app refactor, App Clip expansion, onchain proof, or public network.

Start with:

```text
SAV-E Card schema + local file export/import + agent-readable markdown/json artifacts
```

The app becomes a capture/debug UI. The durable product primitive becomes the card.

## V0 scope

### 1. Add a schema-first card model

Add a shared card model in native Swift and RN/TS if needed.

Card types:

- `place_card`
- `recommendation_card`
- `itinerary_card`
- `review_card`

Minimum fields:

```json
{
  "schema": "save.card.v0",
  "cardType": "place_card",
  "id": "save_...",
  "title": "...",
  "createdAt": "...",
  "createdBy": "local:jhinresh",
  "visibility": "private | public_link | friends | agent_readable",
  "source": {
    "kind": "instagram | luma | google_maps | apple_maps | manual | other",
    "url": "canonical source url"
  },
  "places": [
    {
      "name": "...",
      "address": "",
      "geo": null,
      "status": "source_only | review_candidate | confirmed_place | visited",
      "confidence": 0.0,
      "proofLevel": "source_link | map_confirmed | visited | receipt_backed | payment_backed",
      "evidence": [],
      "missingInfo": []
    }
  ],
  "humanSummary": "...",
  "agentInstructions": [],
  "redactions": [],
  "actions": ["save", "open_maps", "ask_agent", "import"]
}
```

### 2. Map current records into cards

Adapter rules:

- `SaveMemoryRecord.source_only` -> `place_card` with zero confirmed places and `missingInfo`.
- `SaveMemoryRecord.review_candidate` -> `place_card` with `status=review_candidate`.
- Confirmed `Place` -> `place_card` with `status=confirmed_place`, `proofLevel=map_confirmed` if coordinates/google place id exist.
- `Trip + TripStop[]` / RN `SharedTripData` -> `itinerary_card`.
- Future visited/review state -> `review_card`.

### 3. Local artifact export for dogfood

Create local artifacts under an explicit folder, not hidden inside app state only:

```text
~/brain/places/save-cards/
  YYYY-MM-DD-slug.card.json
  YYYY-MM-DD-slug.card.md
```

For iOS, first implementation can export/share the JSON+Markdown payload through Share Sheet or copy-to-clipboard rather than writing directly to `~/brain`.

For Hermes dogfood, a script/importer can save Telegram-analyzed cards directly to the brain folder.

### 4. Card renderer/importer

Minimum V0 renderer:

- Markdown view for humans.
- JSON view for agents.
- RN/web route can later render `save.card.v0`, but V0 does not require public hosting.

Minimum V0 importer:

- Read `.card.json`.
- Validate `schema === save.card.v0`.
- Convert to local vault record or trip preview.

### 5. Keep App Clip second

App Clip is useful for receiving a card link later, but it should consume the card standard, not define it.

Current App Clip only knows `wanderly.app/trip?d=<base64>`. V0 should not expand this until `save.card.v0` exists.

## Out of scope for V0

- Public Yelp-like network.
- Social feed/follow graph.
- Onchain raw memories.
- Receipt/payment proof implementation.
- Encryption migration.
- Full backend migration.
- New reservation/order flows.
- Rebranding every UI string away from Wanderly/SAV-E.

## Implementation slices

### Slice A — schema package / model

- Add `SaveCard` model in Swift.
- Add TS equivalent under `save-rn/src/saveCard.ts` or `src/models.ts`.
- Add sample fixtures under `fixtures/save-cards/`.
- Add validator tests.

Acceptance:

- Fixture JSON validates.
- Swift can encode/decode fixture.
- TS can encode/decode fixture.

### Slice B — native adapter/export

- Convert `SaveMemoryRecord` and `Place` into `SaveCard`.
- Add debug action in `SaveMemoryDebugView` to copy/export card JSON.
- Preserve raw vault records; card is a projection.

Acceptance:

- A saved Instagram reel candidate can produce a `save.card.v0` JSON artifact.
- A confirmed Google Maps place can produce a `save.card.v0` JSON artifact.

### Slice C — RN/web renderer

- Add a simple card renderer that accepts `?card=<base64-json>` or local fixture data.
- Show human summary, places, proof level, source, and actions.
- Include raw JSON panel for agents/debugging.

Acceptance:

- `npm --prefix save-rn run ...` check passes.
- A fixture card renders as a human-readable page.

### Slice D — brain dogfood importer

- Add a small script outside app or under `scripts/`:

```text
save-card import <url-or-json> --out ~/brain/places/save-cards/
```

Acceptance:

- The current IG reel / Luma / Maps examples can be saved as `.card.json` + `.card.md` in brain.
- Hermes can read that folder for later itinerary planning.

## Recommended first PR

Do **Slice A + one fixture + tests only**.

Reason: this repo currently mixes native iOS, RN demo, backend memory, and App Clip. A schema-only PR creates a stable center of gravity without forcing app UX decisions.

## Product wording

Use internally:

```text
SAV-E Cards are agent-readable place memory artifacts.
```

Use externally later:

```text
The beginning of Yelp for AI agents.
```
