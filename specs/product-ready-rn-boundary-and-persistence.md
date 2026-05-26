# Product-Ready RN Boundary And Persistence

## Goal

Move SAV-E from a demo-style RN web surface to a product-ready small-group product with persistent backend storage.

## Product Boundary

### Native iOS

Native iOS remains the full personal SAV-E app:

- Privy-authenticated
- Railway-backed personal places / trips / profile
- Share Extension ingestion
- richer AI parsing and native integrations

### RN Web

RN Web becomes the lightweight collaborative and low-friction SAV-E surface:

- no Privy requirement for first-use
- persistent backend storage for guest bookmarks and trips
- link import, event refinement, trip planning, and trip sharing
- optimized for easy use by friends on a shared URL

RN Web is not required to match native iOS feature-for-feature.

## Persistence Model

RN Web uses a guest session model when `EXPO_PUBLIC_SAVE_API_URL` is configured. It only falls back to local `AsyncStorage` when the backend URL is missing.

### Guest Session

- On first launch, RN Web generates or restores a device-scoped guest id.
- RN Web calls the backend with `x-save-guest-id`; the backend creates the guest profile on first request.
- Guest places and trips persist in Railway/Postgres under that guest profile id.

### Backend Ownership

- Privy-authenticated users keep using the existing bearer-token path.
- RN Web guest users use a low-friction path keyed by `x-save-guest-id`.
- Guest ids should be namespaced, for example `guest_<uuid>`, so they cannot collide with Privy subject ids.

## API Direction

Add guest-aware API handling to the existing Railway backend:

- `GET /places`
- `POST /places`
- `PATCH /places/:id`
- `DELETE /places/:id`
- `GET /trips`
- `POST /trips`
- `PATCH /trips/:id`
- `DELETE /trips/:id`
- `GET /profile`

Auth resolution order:

1. valid Privy bearer token -> authenticated personal profile
2. `x-save-guest-id` header -> guest web profile
3. otherwise reject with 401

## Link Parsing Scope

For product-ready import quality:

- `Google Maps` -> dedicated place parser
- `Apple Maps` -> dedicated place parser
- `Luma` -> dedicated event parser with refinement
- `Instagram` -> platform-aware draft import that preserves source and requires user review
- other links -> draft import fallback

The first product-ready pass does not need full server-side scraping. It does need better source labeling, no fake seeded places, and clear draft semantics for uncertain imports.

## Acceptance Criteria

- RN Web bookmarks survive refresh and browser restart through Railway persistence
- RN Web trips survive refresh and browser restart through Railway persistence
- native iOS behavior remains unchanged
- backend still accepts existing Privy-authenticated native requests
- backend accepts `x-save-guest-id: guest_<uuid>` for RN Web guest persistence
- RN Web can import Instagram links with explicit `sourcePlatform = instagram`
- RN Web can import Google Maps / Apple Maps / Luma links with current specialized handling
- RN Web must not show seeded fake places when authenticated backend data is empty
- RN Web must not prefill local mode with sample places

## Non-Goals

- no attempt to unify native iOS and RN Web into one parity product in this pass
- no Share Extension support in RN Web
- no App Clip equivalent in RN Web
- no social multi-user collaboration in this pass
