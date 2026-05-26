# SAV-E Adaptive Glass Map Drawer

> Last updated: 2026-05-26
> Status: implementation spec

## Product Call

SAV-E's map should feel closer to Apple Maps: the map is the primary surface, the
drawer is translucent and command-first, and persistent map chrome stays minimal.

Unlike the earlier dark-only direction, this pass must follow the user's system
appearance. Light mode remains light; dark mode becomes dark glass.

## Goal

Restyle the map/drawer without changing backend search, persistence, or TestFlight
state.

## In Scope

- Remove persistent top-left/top-right map chrome.
- Move Passport access into the drawer command bar.
- Let the app follow system light/dark appearance.
- Use translucent system material for the drawer and command bar.
- Keep current-location control on the map.
- Reorganize idle drawer content into:
  - command bar;
  - quick action rows;
  - filters;
  - recent queries;
  - suggestions.
- Keep nearby candidates explicit and memory-first behavior unchanged.

## Out of Scope

- WeatherKit or fake weather.
- Backend/search logic changes.
- Place detail card redesign.
- TestFlight build-number or deploy work.

## Acceptance Criteria

- `UIUserInterfaceStyle` no longer forces light mode.
- Map first view has no persistent SAV-E/Passport top chrome.
- Passport remains reachable from the drawer command bar.
- Drawer background and command bar use adaptive translucent material.
- Idle drawer does not show the full command console by default.
- Build and targeted saved-search tests pass.
