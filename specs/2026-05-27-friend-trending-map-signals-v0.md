# Friend and Trending Map Signals v0

## Problem

SAV-E can save personal places and shared lists, but the map still lacks memory-first social discovery: friends' places, trending category signals, referral entry, and a clear "Save to my SAV-E" action.

## Goal

Add a v0 social signal layer that makes friend and trending places visible without turning SAV-E into a generic public feed.

## Scope

- Data model contract for `follows`, `place_social_signals`, and `place_visibility`.
- Drawer surface with `For You`, `Friends`, and `Trending` lenses.
- Place cards show friend or trending signal context.
- Map pins show friend/trending source state.
- Social candidate action: `Save to my SAV-E`.
- Referral profile links:
  - `https://sav-e.app/r/<code>`
  - `https://sav-e.app/u/<handle>?ref=<code>`
- App Clip referral preview for profile + featured places + follow CTA.
- Full app referral handoff stores referrer + intended follow lens for completion after install/open.

## Acceptance Criteria

1. Drawer idle state includes a segmented social lens control for `For You`, `Friends`, and `Trending`.
2. Each social candidate shows source context such as friend saves, trending rank, or referral guide.
3. Social candidates can be saved into the user's own SAV-E without being treated as already-owned memories.
4. Map annotations visually distinguish friend/trending/referral places from private Map Stamps.
5. Saved place cards can display a friend/trending signal when available.
6. Backend schema contains follow graph, place visibility, and place social signal tables.
7. App and App Clip parse referral URLs and route to referral preview/handoff.
8. No real reward-credit accounting, public social feed, comments, or backend ranking algorithm is shipped in this PR.

## Current Truth Boundary

The v0 surface must not imply fake social activity. Until real follow/referral/social-signal data exists:

- `Friends` does not show placeholder friends such as named demo users.
- `Trending` does not show hardcoded ranks or save counts.
- `For You` does not fabricate overlap between friends and trending.
- Empty states explain that real follows, referral handoff, or public Map Stamp activity are required.
- Demo seed places are not acceptable in production UI.

This keeps social discovery trustable. It is better for the drawer to be empty than to show invented friend/trending proof.

## Honest Social Signals v1

Next implementation should make the v0 shell real in this order:

1. `POST /follows`
   - Create a follow from referral handoff or manual profile follow.
   - Store `follower_id`, `following_id`, `lens`, `source`, and optional `referral_code`.

2. `GET /social/signals`
   - Return only real rows from `place_social_signals`.
   - Viewer-specific `Friends` signals require a matching follow edge.
   - `Trending` signals require a minimum threshold before display.

3. Profile/referral preview fetch
   - App Clip referral preview fetches the referrer's public profile and opted-in featured places.
   - Full app handoff completes follow after install/open.

4. Visibility and opt-in
   - Only `friends`, `public_link`, or `public_guide` places with the right signal flags can appear outside the owner account.
   - Private Map Stamps never become social candidates.

5. UI honesty
   - If the backend returns no signals, show empty state copy.
   - Do not backfill with static social seeds.
   - Every social candidate keeps `Save to my SAV-E` as an explicit action.

## Verification

- iOS simulator build for `Wanderly`.
- iOS simulator build for `WanderlyClip`.
- Backend TypeScript build.
- `git diff --check`.

## Follow-Up

- Backend endpoints for `GET /social/signals`, `POST /follows`, and referral reward receipts.
- Production `sav-e.app` AASA/App Clip domain setup.
- Real profile/featured-place fetch for referral previews.
