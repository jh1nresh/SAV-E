# SAV-E TREK Provider + Simplified Trip Flow v0

Date: 2026-07-31
Status: adapter core implemented; production connection gated
Repo: `/Users/jhinresh/projects/wanderly-current`

## Decision

SAV-E will not copy or embed TREK. It will treat an independently deployed,
unmodified TREK instance as an optional planning provider over its public MCP
boundary:

```text
Clue -> Review -> confirmed Map Stamp
                         |
                         v
                TrekPlanningAdapter
                         |
              MCP Streamable HTTP + OAuth 2.1
                         |
               unmodified TREK service
                         |
            Trip / Days / Places / Order / Share
```

SAV-E remains the truth for clues, evidence, confirmation, and private place
memory. A TREK trip is an explicit user-created projection of confirmed Map
Stamps, not a second place-memory database and not an automatic dual write.

The inspected upstream contract is
[`liketrek/TREK`](https://github.com/liketrek/TREK) at commit
`e60427f813dc35f688d5d9169b79ac8c43974719` (latest release `v3.4.1`). TREK is
AGPL-3.0; this repository consumes the separately running service through MCP
and does not copy its source, tests, components, or assets. This is a technical
containment decision, not legal advice.

## Required brief

### Customer-paid job / observed failure

> Turn confirmed travel places into a usable day-by-day trip without asking the
> user to learn or maintain two planning products.

The current app makes the core handoff harder than it needs to be. It exposes
four root modes (`Home / Saves / Trips / Map`), then four more modes inside a
Trip (`Plan / Map / Inbox / Share`), while Review and Map search also enter a
multi-state drawer. `Inbox` duplicates the Review queue concept and `Share` is
an action presented as a persistent workspace.

### Classification

Integration foundation plus product-flow simplification. This slice implements
the provider-neutral adapter core and its failure receipts. It does not change
production navigation or expose a live TREK connection.

### Demand, pricing, and first distribution

- Demand proof: direct founder request and repeated SAV-E/TREK planning tests;
  external paid demand is not yet proven.
- Pricing/paywall: unchanged. Do not gate planning or add provider credits in
  this slice.
- First distribution: founder dogfood through an internal/TestFlight build only
  after the OAuth, idempotency, and UI slices pass. Public launch is separate.

### Scope

In this slice:

- strict confirmed-Map-Stamp input contract;
- deterministic TREK MCP tool orchestration;
- private-by-default sharing;
- bounded, redacted execution receipt;
- no automatic retry of non-idempotent TREK tools;
- UX complexity ruling and next-slice acceptance criteria.

Out of scope:

- OAuth redirect/callback and token persistence;
- a production API route or background sync;
- a database migration or remote-trip mapping;
- iOS settings, connection UI, navigation changes, or TestFlight;
- bookings, budget, packing, chat, reservations, transport, or purchasing;
- copying, vendoring, modifying, or deploying TREK;
- choosing or operating a TREK host for the user.

### Human approval still required

- choose/configure the TREK instance and public callback origin;
- approve provider credentials and encrypted-token storage;
- schema migration, deployment, merge, TestFlight, or production enablement;
- any public share-link creation by a real account.

## Adapter contract implemented in this slice

`backend/src/trekPlanningAdapter.ts` consumes only:

- local request and Trip UUIDs;
- Trip title, optional date range, and currency;
- confirmed Map Stamp UUID, public venue name/address/coordinates;
- explicit day, order, and optional start/end time;
- explicit `private` or `map_only` share mode.

The input type intentionally has no source URL, social handle, raw clue,
private note, screenshot, or user-memory field. Runtime validation rejects
unexpected fields rather than silently forwarding them.

The adapter calls only these upstream tools:

1. `create_trip`
2. `get_trip_summary` to resolve generated day IDs
3. `create_and_assign_place` for each confirmed Map Stamp
4. `update_assignment_time` when a time is present
5. `reorder_day_assignments` for multi-stop days
6. `create_share_link` only for explicit `map_only`, with bookings, packing,
   budget, and collaboration disabled
7. `get_trip_summary` for the final count/identity check

Required OAuth scopes are `trips:write` and `places:write`; `trips:share` is
requested only if the user explicitly enables TREK sharing. Delete scope is
not part of v0.

### Failure and retry invariant

TREK marks `create_trip` and `create_and_assign_place` non-idempotent. The
adapter therefore never retries a failed call. It returns a receipt containing
the local request, remote Trip ID when known, bounded local-to-remote place and
assignment mappings, completed tool names, imported count, failed step, safe
error code, and `manual_only` retry policy. It never places a public share token
or raw provider error in the receipt.

This makes partial failure visible but does not yet make production execution
safe. A production endpoint remains blocked until a durable local-to-remote
mapping exists.

## Production connection gate

The next backend slice must use the official Model Context Protocol TypeScript
client instead of implementing Streamable HTTP or OAuth by hand. Do not add the
SDK until this connection slice is approved: the official packages are in a
version transition, add a material dependency tree, and there is no callback
origin or token store in SAV-E today.

### Required connection design

1. Support one founder-configured HTTPS TREK MCP origin in v0. Do not accept an
   arbitrary user-supplied server URL; that would create an SSRF boundary.
2. Start OAuth from an authenticated SAV-E account and bind state, PKCE verifier,
   callback, client registration, and tokens to that account and connection.
3. Keep access and refresh tokens on the backend, encrypted at rest. Never put
   them in iOS defaults, analytics, logs, receipts, or a share link.
4. Request the minimum scopes above. Ask for `trips:share` only at the moment the
   user chooses TREK sharing.
5. Add a disconnect/revoke path and a kill switch. Connection failure must not
   lock or corrupt SAV-E Trips.
6. Pin and review the official MCP client version, license, advisories, and
   transitive dependencies; run the repository audit before adoption.

The eventual execution route must accept only a local Trip ID and explicit
share decision from iOS. The backend must load the owner-scoped Trip and Places
and construct `TrekPlanningRequest`; client-authored confirmation state, place
identity, coordinates, or ordering are not authoritative.

### Required idempotency record

Before exposing execution, persist a unique mapping similar to:

```text
(user_id, local_trip_id, trek_connection_id) ->
request_id, remote_trip_id, status, completed_step, imported_place_count
```

The execution route must transactionally claim `request_id`. A repeated request
must load the existing mapping and inspect the remote summary; it must never
call `create_trip` again just because a response was lost. Do not automatically
delete a partial remote trip as rollback.

## UX complexity ruling

Yes: the planning portion is currently too complex, but the answer is not to
make SAV-E map-first or to expose more TREK screens.

Keep the already approved root shell for now:

```text
Home | Saves | Trips | Map
```

Reduce the Trip workspace to:

```text
Plan | Map
```

- Move Trip `Inbox` back to the existing Saves/Review system. A candidate may
  retain an intended Trip ID, but there is still only one Review queue.
- Turn Trip `Share` into a top-right action on Plan and Map. A user shares at a
  moment; they do not live inside a Share workspace.
- Keep one global paste/share-link entry. Do not add a TREK-specific capture
  button, settings tab, or provider tab.
- Present `Continue in TREK` only after a Trip contains confirmed Map Stamps.
  First use starts connection; later use shows progress and the execution
  receipt. Provider details belong in Passport > Connections, not primary nav.
- Keep Map as a supporting spatial view. SAV-E is for deciding and organizing
  places, not turn-by-turn navigation.

The root `Trips` tab is not removed in the same change. It remains the clear
place to resume planning, and removing it while adding an external provider
would confound the usability test. Reconsider moving Trips under Saves only
after measuring the simplified two-tab Trip workspace.

### Target user flow

```text
Paste/share link
-> Review one clue
-> Confirm Map Stamp
-> Add to an existing/new Trip, or keep in SAV-E
-> Plan (day/order) <-> Map
-> optional Continue in TREK
-> optional Share action
```

No provider terminology is required until the optional `Continue in TREK`
action. SAV-E remains fully usable when TREK is disconnected or unavailable.

## Failure fixtures and acceptance criteria

Adapter core fixtures in this slice:

1. Unconfirmed Review Candidate is rejected before any transport call.
2. Unexpected `sourceUrl` or private `note` is rejected before transport.
3. Map Stamps are copied in deterministic day/order order.
4. Share stays private unless `map_only` is explicit.
5. A partial remote failure stops immediately and records the remote Trip ID and
   imported count without retrying.
6. Missing or malformed TREK day/assignment responses fail closed.

Production connection acceptance:

1. One user can connect and disconnect one configured TREK account with OAuth
   2.1/PKCE; another SAV-E user cannot access that connection.
2. Replaying the same `request_id` creates exactly one remote Trip.
3. A lost response resumes from the durable mapping and remote summary.
4. TREK downtime leaves the SAV-E Trip editable and retry is user-controlled.
5. Only confirmed, owner-scoped Map Stamps cross the boundary.
6. Sharing is private by default and requires a separate explicit action/scope.
7. Tokens and share tokens are absent from logs, analytics, errors, and receipts.

UX acceptance for the later iOS slice:

1. A Trip exposes only Plan and Map as persistent tabs.
2. Review remains reachable through Saves and the global capture flow; no second
   Trip Inbox queue exists.
3. Share is an action, not a persistent tab.
4. Back/dismiss always returns to the originating root or Trip tab.
5. Founder dogfood can complete link -> Review -> confirm -> Trip -> reopen
   without knowing what MCP or TREK is.

Measure median completion time and abandonment at `Review`, `Add to Trip`, and
`Continue in TREK`, plus drawer-open-without-action and back-navigation failure.

## Verification and security receipt

This backend-only slice:

```bash
cd backend
npm run build
node --test dist/trekPlanningAdapter.test.js
npm test
npm audit --omit=dev
git diff --check
```

- Xcode context: N/A; no Swift/Xcode source changes in this slice.
- Dependency scan: no dependency added.
- Reachable production path: none; adapter is not registered in `server.ts`.
- Secrets: none introduced, read, logged, or persisted.
- Data boundary: only confirmed public venue identity and explicit trip fields;
  private clue evidence is excluded by type and runtime allowlist.
- Network boundary: no MCP URL or outbound transport is installed in this slice.
- Residual risk: partial TREK side effects are possible once execution is wired;
  the durable idempotency mapping and OAuth connection gate are mandatory first.

## Done for this slice

- adapter and exact TREK tool mapping compile;
- focused fixtures pass;
- full backend suite and dependency audit pass;
- spec records the simplified `Plan | Map` direction;
- no route, token store, schema, iOS navigation, deployment, or TREK source copy
  is introduced.
