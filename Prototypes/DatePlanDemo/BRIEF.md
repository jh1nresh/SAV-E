# Personal map and explicit friends outing — build 148 candidate

## Goal and delivery boundary

The user requested real data and Apple Maps pins, with a personal map by default and an explicit friends outing mode. Keep Saved / Map / Passport and a useful Guide without authored 3D in this preview. Personal saved places, search candidates, team candidates and friends' shared posts must remain distinguishable. Planning or adding a team venue never creates a personal Map Stamp or visit.

Delivery is Draft PR #343, stacked on #342 (`codex/xinyi-streetlife-preview`), plus the authorized signed Debug update of the user's existing Savvy app. Build 146 was the isolated fictional date demo. Build 147 has been installed and launched through the normal account gate; a physical-device screenshot showed personal mode and 85 actual saved records. Build 148 is the current UI refinement candidate, signed-build PASS; installation/render verification remains pending. The 25 new native tests passed on iOS26.5; the borrowed simulator was shut down. These tests do not establish real multi-user writes or location-permission interaction.

Keep #343 Draft and GitHub Actions disabled. Required hosted CI is not green; the PR is not merge-ready. No merge, backend/schema deployment, App Store or TestFlight release. No agent-side account mutation or live-data export belongs to this work. Preserve `com.wanderly.app`, its extensions, entitlements and containers; do not uninstall, reset accounts or migrate user data to demonstrate it.

## Separate entries and data

| Surface | Entry and data | Purpose |
| --- | --- | --- |
| Main Debug phone preview, build 148 candidate | Normal `SaveApp` → existing authenticated/account gate → `ContentView` → `LivePlanningMapRoot`; the same production `MapViewModel` supplies saved places | Real personal map and explicit friends outing |
| Standalone `SavvyDateDemo` | Separate `SavvyDateDemoApp` / `DateDemoRoot`, `Core/` fixtures and in-memory personas | Historical mock: fictional venues, An, local votes, sample budgets and illustrative travel |

`Main/` live UI and new native tests are guarded by `DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW`. The phone flag no longer replaces `SaveApp` with the standalone entry. Ordinary main Debug and main Release do not select the live preview or fixture flow. No Release behavior change is intended; generic builds must verify isolation. Standalone evidence does not establish real-account behavior.

## Real-account contract

- **Personal default:** project the current account's actual saved Places into stable annotations. Only valid, nonzero WGS84 coordinates accepted by `Place.isMapKitMappable` become pins. Do not pretend GCJ-02/BD-09 is WGS84 or invent a location. Unmappable records remain in their source collection.
- **Native discovery:** Apple supplies the standard basemap and its POIs; `MKLocalSearch` supplies real results. Search candidates remain separate from saved pins. Venue cards can hand off walking navigation to Apple Maps. Provider/network failures remain visible rather than being replaced by fixtures.
- **Explicit friends mode:** read actual server-authorized collaborative lists, selected-list items, roster and available friends' shared-post feed through account-bound `LiveOutingModel`. Do not use `MapViewModel.collaborativeLists` or the legacy global list cache. Empty accounts have no invented An, team, member, recommendation or votes.
- **Explicit writes:** create list, join by code, add venue and generate/share invitation are distinct user actions through existing authenticated APIs. ACL roles govern editing/invitation. Viewing pins, switching modes or generating routes performs none of these writes. There is no realtime voting, consensus, presence or friend-location sharing.
- **Venue-only payload:** share name/address/coordinates/category and necessary typed source identity. Strip private notes, ratings, source URLs, photos and sender memory. A friend's want-to-go/visited state is not the recipient's save, visit or recommendation.
- **Account lifecycle:** reuse main owner/session generation; invalidate stale async projections and routes on session changes, cancellation, mode exit or revoked access. Do not persist shared posts as personal Places. Refresh must not repeat acknowledged mutations; uncertain outcomes require explicit retry handling.
- **Account controls:** reuse compact Profile settings for profile controls, sign-out and confirmed account deletion, without exposing legacy Profile list UI/cache.

## Guide contract

The user selects 2–6 actual team venues in order. `MKDirections` requests walking routes; returned polylines and estimated travel times feed the map/timeline. The current 60-minute stop allowance is explicit planning input, not venue-specific duration or opening-hours evidence. A failed route request displays an error, never fabricated travel.

Departure, start and next-stop progression are user-controlled. This is not live navigation, automatic visit recording or proof that every member agreed. Menu, prices, total budget, hours, booking availability and backups remain unverified. Do not copy standalone samples into real venue cards or treat unknown prices as zero. No remote AI, MCP guide service or new backend is introduced.

## Scope and verification

Scope includes `Main/` projections, outing model, map/search/Guide UI and route helper; narrow main SaveApp/ContentView/compact Profile integration; project membership/version 148; and native tests in `Tests/SAVETests`. Standalone `Core/`, `Sources/`, checks and UI tests remain a distinct fixture prototype. Preserve unrelated work and existing 3D sources; no 3D optimization or backend change belongs to this slice.

There are currently **25 new native test methods in source**: 11 `LiveMapPlaceTests` and 14 `LiveOutingModelTests`. They use real app/framework types with redacted/injected fixtures for coordinates, stable IDs, sharing, ACL, session/cancellation and mutation acknowledgements. All 25 executed with 0 failures; the native test build also passed. Static parsing, host checks and historical mock UI passes do not substitute for that run.

The controller exclusively owns builds/caches, one simulator/device and installation. Respect the repo's 10 GiB floor before runtime gates. Verify ordinary-main isolation, preview compilation, native tests, personal-default/explicit-friends UI, identity/entitlements and the authorized 147 install/launch/rendered behavior separately. Do not exercise create/join/add/invite/delete against an actual account merely to collect unattended evidence.

Receipts/screenshots/recordings remain local under ignored `Evidence/` or task-local evidence paths. Do not commit private payloads. Report source, local checks, hosted CI, installed version, launch and rendered evidence separately. The endpoint is a reviewable Draft and verified local/device preview, never merge or release.

Demand evidence is the user's explicit request for their own map and optional group trips. Pricing/paywall remains unchanged and unvalidated. First distribution is the Draft and the user's Debug preview, not a public rollout.

## Detailed Implementation Plan — focused UI pass, build 148

The user reported missing location control, oversized map chrome and inconsistent Saved/Passport styling. Retain real data, personal default, explicit friends mode and the glowing Saved / Map / Passport dock with search on its left. This pass improves these existing surfaces; it does not certify the entire app as finished.

1. Controller owns `Main/LivePlanningMapRoot.swift`, `Sources/DemoTheme.swift`, `Sources/DatePlanDemoApp.swift`, project membership/version and this brief. Remove the large decorative map heading; use one compact 52pt personal/group selector. Reduce personal summary to one 44pt interactive row with counts; keep empty/unlocated notices only when relevant. At world scale, native Marker symbols distinguish bookmarked saves from question-mark candidates; below 20km camera distance, retain anchored venue annotations. Both paths open the same source-typed place card. Source state must be accessible without relying on color. Do not change camera identity or data adapters.
2. Location leaf owns new `Main/LiveMapLocationControl.swift`: a 48pt recenter control calls existing LocationService only after explicit tap, displays loading/error/denied recovery, and applies only a fresh valid fix to the camera. Session generation and cancellation prevent late updates. Background/leave/auth changes cancel the view's request; transient permission-dialog inactivity must not strand loading. Settings opens only after its explicit alert action. No persisted/shared location or background tracking.
3. Library leaf owns new `Main/LivePlanningLibrary.swift`: `LivePlanningLibraryView(places:isLoading:onOpen:onCapture:)` renders the provided account places, local name/address filtering and actual saved/visited state. `LivePlanningPassportView(places:onOpenLibrary:onOpenAccount:)` exposes real counts and existing account controls without fictional identity or achievements. Use existing safe/cached photo presentation where available; no new image provider or invented photos. Keep stable Place IDs, full-row actions, >=44pt targets, wrapping and scrollability.
4. Main preview `DateTheme` aliases the existing adaptive CityMVPStyle tokens: ink, muted, canvas, surface, panel, blue and actionFill. The standalone mock retains its own palette. Reuse dock glow/matched geometry; reduce motion remains respected. Remove forced light appearance in the live preview. Native SwiftUI remains the stack; ui-sdk and Modern Web Guidance are web-only and do not authorize inserting a web layer or installing packages here.
5. Regenerate the main project after new files exist and set build148. Compile normal main plus the flagged Debug phone preview with the exclusively owned cache. Existing 25 native projection/ACL tests have passed and remain valid if those models do not change. Check fresh location/permission/cancellation code and map source states independently. Capture same-binary normal-size personal, explicit group, Saved and Passport phone screens using UI-only preview launch arguments; these must never bypass the account gate or seed data. Restore normal launch to personal mode afterward.
6. Freeze and independently inspect the diff; fix supported issues and recheck affected builds. Update the existing Draft #343 and install only the authorized main Savvy on the connected phone. Required hosted CI remains unavailable while Actions stays disabled. No merge, backend deployment, App Store/TestFlight, automatic group writes or unrelated 3D changes.

### Current local verification

- 25 native tests: PASS (11 projection, 14 outing, iOS26.5). Models/tests unchanged by the 148 UI pass.
- Normal main generic simulator build: PASS at 148 (preview flag absent).
- Signed build148: PASS, using the existing development identity and no provisioning updates.
- Independent bounded Goldfish source review: PASS after fixing adaptive-card contrast, returning search results to the map, and permission-dialog inactivity handling. Render/interaction acceptance is separate and pending.
- Main Savvy147 installed and launched without uninstall/reset; real personal data rendered. Device now locked; 148 install/capture awaits unlock. No real group mutation or permission flow was exercised automatically.
