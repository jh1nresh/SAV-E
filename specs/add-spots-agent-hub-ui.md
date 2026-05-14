# Add Spots Agent Hub UI

> Last updated: 2026-05-13

## Goal

Make SAV-E's native iOS import surface feel closer to a product-ready travel app: users should immediately see where to add social links, pasted URLs, notes, screenshots, manual places, and agent commands.

## Product Direction

Borrow Roamy's clear "Add Spots" hierarchy, not its exact visual design or any unsupported scraping promise.

SAV-E should present an import hub inside the existing AI drawer because the product already uses the drawer as the main command surface.

## Requirements

- Preserve the map category bar and profile entry.
- Keep `Ask about your places...` as the top command input.
- Add a clear `Add Spots` section in the expanded idle drawer.
- Include entry points for:
  - Social Link
  - Paste URL
  - Notes
  - Screenshots
  - Search Location
  - Agent Command
- Social/video copy must say SAV-E uses public metadata/share extension first, not video analysis.
- `Paste URL` should read the clipboard when a URL is available and route it into the agent prompt.
- Agent-oriented entry points should populate useful prompts instead of being decorative.
- Do not implement unsupported TikTok/Instagram in-app browsing in this patch.

## Acceptance Criteria

- Opening the drawer shows a polished Add Spots hub without hiding My Places or Import.
- Tap targets are at least 44pt.
- Text fits within compact iPhone widths.
- No fake metrics, no emoji icons, no purple/blue generic AI palette.
- `xcodebuild` for the main app passes.
