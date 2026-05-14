# Agentic Add Spots Drawer

> Last updated: 2026-05-14

## Goal

Make SAV-E's Add Spots surface feel like an agent command drawer instead of a static import menu, while preserving the conversational input as the primary product surface.

SAV-E should remain listable as an agent/workflow in Dojo: users give it links, media evidence, notes, or place intents; SAV-E investigates and returns reviewable candidates or plans.

## Product Direction

SAV-E is not a Roamy-style collection-first travel app. SAV-E is an agent-first place-saving workflow:

```text
Input link/media/note
-> SAV-E investigates
-> candidate places with evidence
-> user confirms save
-> SAV-E plans or shares a trip
```

The UI should communicate workflow triggers and agent judgment, not just buckets of saved data.

## Requirements

- Keep `Ask about your places...` as the top conversational input.
- Keep Add Spots inside the expanded drawer.
- Replace static Add Spots cards with agent command cards.
- Every card should populate a specific, actionable prompt.
- The command cards should cover:
  - investigate a social/video link
  - import a public URL from clipboard
  - investigate media evidence
  - turn notes into review candidates
  - find the real venue
  - plan from saved places
- Add a `Review candidates` section or empty state.
- Make candidate review explicit: results are not saved automatically.
- Do not add a backend candidate table in this patch.
- Do not implement automatic platform video downloading in this patch.

## Acceptance Criteria

- The idle drawer still opens with the conversational search bar.
- Add Spots uses agent/workflow language rather than generic import-card language.
- Tapping each Add Spots command fills a clear prompt.
- `Review candidates` appears as an agent output staging area/empty state.
- Copy says candidates require user confirmation before save.
- Existing My Places and Google Takeout import entry points remain available.
- `xcodebuild` for the main iOS app passes.
