# SAV-E Glass Drawer and Saved Category Lens

> Last updated: 2026-05-27
> Status: implementation spec

## Product Call

The map should remain the primary surface. The drawer should feel like adaptive
glass over the map, not an opaque notebook panel.

Saved places should be grouped by category because SAV-E is a spatial memory
product. A user should be able to quickly ask "show my cafes" or "show my food
places" without opening a full list first.

## Goal

Polish the existing SwiftUI map drawer and add a Saved category lens in the
drawer.

## In Scope

- Make the drawer background and command bar more translucent/adaptive.
- Keep the drawer readable in light and dark system appearance.
- Change the Saved quick action to open a drawer-native Saved category view.
- Show category rows with counts based on existing saved places.
- Tapping a category toggles the existing map category filter.
- Keep a secondary action to open the full saved list.

## Out of Scope

- New backend schema.
- New place taxonomy.
- Changing how places are saved or imported.
- Merging existing open PRs.

## Acceptance Criteria

1. Drawer surface and command bar use visible glass material with lighter tint.
2. Saved quick action no longer jumps directly to a separate sheet.
3. Saved category view shows all non-empty saved categories and counts.
4. Category taps reuse the existing `selectedCategories` filter.
5. Full saved list remains reachable.
6. iOS simulator build passes.
