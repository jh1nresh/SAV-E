# Personal map, icon-aligned UI and interactive venue cards — build 150

## Contract and delivery

The user wants a real personal map by default, explicit friends outings, Saved / Map / Passport with search on the left, business-photo pins and a coherent style matching the existing coral/cream Savvy icon. The map must remain mounted across tabs. Opening a pin must retain its click-triggered pop and wobble; pan/zoom must not trigger that animation or move the geographic anchor. Place details should show location context and original notes rather than a wall of generated text.

Work is limited to the existing Draft #343 on `codex/date-plan-phone-preview`, stacked on #342. Intended predecessor order: #339 → #340 → #342 → #343. The separate City Lab app is retired as a delivery target; preserve existing 3D sources outside this preview. The authorized phone target is the user's existing main Savvy `com.wanderly.app`. No uninstall, account reset, backend/schema deployment, merge, App Store or TestFlight release. GitHub Actions stays disabled; hosted required CI is unavailable and the Draft is not merge-ready.

## Entry and state boundaries

The normal SaveApp/account gate supplies the same production MapViewModel to the live preview. New main UI requires `DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW`; ordinary Debug and Release do not select it. The standalone DateDemoRoot remains an independent historical mock, with explicit fictional people, venues and budgets. Those fixtures are not copied into the real account UI.

Only actual account Places with valid nonzero WGS84 coordinates become saved pins; unlocated clues remain in their collection. Search and native Apple POIs are candidates, not confirmed Map Stamps or visits. Native selection uses MapFeature → MKMapItemRequest; custom annotations use Button actions. Existing saved venues resolve to their real account IDs, notes and visit state. Candidate confirmation explicitly uses the canonical save path, preserving duplicate handling, account/session guards and the existing cap. Opening, browsing, routing or sharing does not confirm a save or visit.

Personal is the default. Explicit Friends mode reads actual ACL-authorized lists, members and shared posts through the owner/session-bound LiveOutingModel, without the legacy global collaborative cache. No fictional friends, votes, endorsements or live locations. Create, join, invite and add-to-list remain separate explicit actions. Venue-only payloads exclude private notes, ratings, photos and sender memory. Session changes, cancellation, mode exit and revoked access invalidate stale data and async results. Native POI lookups cancel when another sheet covers the map.

## Surface contract

- SaveBrandUI in Color+Theme.swift owns the preview's adaptive coral/cream/charcoal palette. DateTheme aliases it only in the main Debug preview. Preserve the glowing three-tab switch, globe Map icon and Passport; no doodle paper or rough borders.
- Round pin artwork uses the existing CityPinArtwork spring, bottom-anchored selection scale and short click-triggered wobble. Reduce Motion disables pop/wobble; map gestures do not restart them. Native pan, zoom, rotation and pitch stay available.
- Place cards use a native Apple mini-map, actual address, compact save/open/directions actions and optional existing business photo. Original notes remain literal, initially four lines, expandable; no generated rewrite. Keep Apple attribution visible.
- Business photos come only from existing businessPhotoUrls after the current map-safe source policy. Do not promote source screenshots to business photos, fetch new providers or invent images. Missing/restricted/failed photos use category fallback. Actual provider-photo coverage remains unknown.
- The explicit recenter button requests a fresh location only after a tap, survives transient permission-dialog inactivity and fences late fixes by owner/session/request. It neither persists nor shares location.
- Saved, Passport, search, venue cards and compact account/edit/language/privacy routes use the same palette and app-owned English/Traditional Chinese copy. User names, addresses and notes retain their language. Deeper legacy tutorial/paywall/debug routes are not certified restyled.
- Privacy controls retain real callbacks. Per-place visibility writes are serialized; failure rolls back only the affected field after reacquiring the current owner/place, and acknowledged writes are not falsely rolled back.

## Guide and known limits

The Guide uses selected real team venues and MKDirections walking routes. Each stop's 60-minute allowance is an explicit planning assumption. Route failures remain errors; no fabricated travel, menu, hours or budget. Start/next-stop progression is manual. No remote AI, MCP service, consensus voting, automatic visits or background tracking is introduced. Leaving/backgrounding this preview currently cancels its transient Guide plan; navigation-return continuity remains unfinished.

Demand evidence is the user's explicit personal-map and optional group-outing request. Pricing/paywall is unchanged and unvalidated. First distribution is this Draft and the authorized Debug phone installation, not a public rollout.

## Verification and proof boundaries

Controller owns the build cache and one runtime/device lease. Repo runtime floor: 10 GiB free. Use the leased existing cache, serialized builds, one borrowed headless simulator, and verify Shutdown. Local evidence is ignored; do not commit real-account payloads/counts/screenshots.

149 baseline: generic normal-main build and signed device build passed. Main Savvy149 was installed with the existing identity/entitlements; account-screen rendering was not verified. Full SAVETests: 1,923 total, 1,920 passed, 3 expected skips, no failures. Skips cover actual device file protection, opt-in live AI and UI performance measurement. Component-only light/dark Saved and Passport renders passed; they do not prove the whole app, real interactions, 60fps or photo availability.

150: normal-main generic simulator build, flagged native test-build and signed generic-device build passed. Full SAVETests passed: 1,932 total, 1,929 passed, 3 expected skips, no failures. The new ordinary-save transport tests hold the real URLSession token provider and reject owner/generation changes before POST; duplicate projection tests preserve actual account memory. All six component light/dark renders were inspected, including the native-map place card. The borrowed simulator is Shutdown. Independent source/local-evidence review passed for the frozen product files.

Main Savvy150 was installed and launched normally; metadata readback confirms bundle/version. Identity, App Group and keychain groups match the existing app. No actual-device screenshot was taken during this slice because other foreground apps had appeared during earlier unattended captures. Actual native POI taps, custom-pin pop/wobble feel, note expansion and GPS still require interaction evidence; source and component renders do not establish those claims. Hosted CI and full integration/0.90 visual acceptance remain unavailable while Actions is disabled. Generic build, unit tests, component renders, actual device taps, installed bundle, hosted CI and release remain separate claims. Do not exercise real create/join/add/invite/profile/visibility/delete merely to collect unattended evidence.
