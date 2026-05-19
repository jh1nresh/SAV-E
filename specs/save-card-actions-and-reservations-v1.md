# SAV-E Card Actions and Reservations V1

> Created: 2026-05-19
> Depends on: `specs/agent-native-save-cards-v0.md`, `specs/agent-callable-memory-contract.md`
> Status: proposed implementation slice

## Product decision

V1 should add reservation/action semantics **after** `save.card.v0`, not turn SAV-E back into an app or booking product.

```text
save.card.v0
-> action capability binding
-> availability quote
-> user-confirmed handoff/request
-> reservation receipt
-> later visit/review/proof
```

SAV-E remains the place memory/card layer. SLR/SLL-R is the action rail. Jiagon/OrderProof receives completed action/visit proofs later.

## Naming

Backend canonical name remains `SLR` from `agent-callable-memory-contract.md`:

```text
SLR = seller-side / service-side lookup and reservation capability family
```

Product copy may say `SLL-R`, but implementation should keep the existing backend family `SLR` to avoid schema churn.

## Current repo evidence

The backend already has the primitives needed for V1:

- `backend/sql/schema.sql`
  - `agent_capabilities`
  - `agent_tool_calls`
  - seeded `SLR.restaurants.search_availability`
  - `risk_level in ('read', 'quote', 'hold', 'purchase')`
- `backend/src/server.ts`
  - `GET /agents/capabilities`
  - `GET /agents/tool-calls`
  - `POST /agents/tool-calls`
- `specs/agent-callable-memory-contract.md`
  - explicitly scopes agent calls without real booking/payment execution

V1 should reuse these rather than create a parallel reservation system.

## Core split

```text
SAV-E Card = stable place/recommendation/itinerary memory artifact
SLR Action = time-sensitive availability/reservation attempt
Receipt    = durable proof that an action happened
```

Do not store expiring availability inside the card as if it were durable place memory. Store it as a quote/tool-call result linked to the card.

## V1 scope

### 1. Extend card actions

`save.card.v0` should allow structured actions, not just string labels.

Example:

```json
{
  "actions": [
    {
      "type": "check_availability",
      "capability": "SLR.restaurants.search_availability",
      "riskLevel": "quote",
      "inputHints": {
        "partySizeRequired": true,
        "dateTimeRequired": true
      }
    },
    {
      "type": "request_reservation",
      "capability": "SLR.restaurants.request_reservation",
      "riskLevel": "hold",
      "requiresUserConfirmation": true
    }
  ]
}
```

V1 should start with `check_availability` only. `request_reservation` can be modeled in schema but not executed until a later PR.

### 2. Define `reservation.quote.v0`

A quote is a temporary answer from SLR. It may be stale. It is not proof of a booking.

Minimum shape:

```json
{
  "schema": "reservation.quote.v0",
  "id": "quote_...",
  "cardId": "save_...",
  "placeRef": {
    "name": "...",
    "sourceUrl": "..."
  },
  "requestedAt": "2026-05-19T00:00:00Z",
  "partySize": 2,
  "dateTime": "2026-05-19T19:30:00-07:00",
  "provider": "resy | opentable | sevenrooms | google | phone | manual | unknown",
  "status": "available | unavailable | needs_handoff | error | unknown",
  "options": [
    {
      "time": "19:30",
      "partySize": 2,
      "depositRequired": false,
      "cancellationPolicy": "unknown",
      "handoffUrl": "https://..."
    }
  ],
  "expiresAt": "2026-05-19T00:10:00Z",
  "riskLevel": "quote",
  "sideEffect": false
}
```

### 3. Define future `reservation.receipt.v0`

A receipt is durable proof that the user confirmed a side-effectful action.

Minimum shape for later PRs:

```json
{
  "schema": "reservation.receipt.v0",
  "id": "res_...",
  "cardId": "save_...",
  "quoteId": "quote_...",
  "placeRef": {
    "name": "...",
    "sourceUrl": "..."
  },
  "provider": "resy | opentable | sevenrooms | google | phone | manual | unknown",
  "reservationTime": "2026-05-19T19:30:00-07:00",
  "partySize": 2,
  "status": "requested | confirmed | waitlisted | cancelled | failed",
  "confirmationCode": "redacted-or-empty",
  "proofLevel": "reservation_requested | reservation_confirmed | manual_confirmation",
  "userConfirmed": true,
  "sideEffect": true,
  "createdAt": "2026-05-19T00:00:00Z"
}
```

V1 should only define this shape; it should not execute booking APIs.

### 4. Use existing `agent_tool_calls`

Availability checks should be stored as tool-call traces:

```json
{
  "capability_id": "SLR.restaurants.search_availability",
  "input": {
    "cardId": "save_...",
    "place": {},
    "partySize": 2,
    "dateTime": "...",
    "constraints": {
      "allowHandoff": true,
      "autoBook": false,
      "maxDeposit": 0
    }
  },
  "output": {
    "schema": "reservation.quote.v0",
    "options": [],
    "status": "needs_handoff"
  },
  "status": "succeeded"
}
```

This keeps availability/action results auditable without polluting the card/vault.

## Risk policy

Use risk levels consistently:

```text
read     = no external side effect; local/card/memory read
quote    = availability/price lookup; no booking/payment
hold     = temporary hold, form prefill, waitlist, or external state change without payment
purchase = booking/order/payment or any paid/non-refundable side effect
```

Rules:

- `read` and local card generation can be automatic.
- `quote` can run with user intent but should not book.
- `hold` requires explicit user confirmation.
- `purchase` requires explicit user confirmation at action time and must not be hidden in background automation.
- Any deposit, cancellation fee, no-show risk, login, phone call, payment, or irreversible reservation is not V1.

## State machine

```text
save.card.v0
-> availability_requested
-> reservation.quote.v0
-> user_handoff_opened | reservation_request_pending
-> reservation.receipt.v0
-> visit_receipt.v0
-> review_card
-> reputation_update
```

V1 should implement only through `reservation.quote.v0` and handoff metadata.

## V1 implementation slices

### Slice A — schema docs and fixtures

Add fixtures:

```text
fixtures/save-actions/restaurant-availability-quote.available.json
fixtures/save-actions/restaurant-availability-quote.needs-handoff.json
fixtures/save-actions/reservation-receipt.future.json
```

Acceptance:

- Fixtures validate shape and make side-effect boundaries explicit.
- Quote fixture has `sideEffect: false`.
- Receipt fixture has `sideEffect: true` and `userConfirmed: true`.

### Slice B — TS/Swift models

Add minimal Codable/TS types for:

- `SaveCardAction`
- `ReservationQuote`
- `ReservationReceipt`

Acceptance:

- Existing `SaveCard` actions can be strings or structured actions during migration, or V1 migrates fixtures to structured actions in one bounded PR.
- Fixture decode/encode passes in both TS and Swift where practical.

### Slice C — backend capability binding

Reuse `agent_capabilities` and `agent_tool_calls`.

Acceptance:

- `SLR.restaurants.search_availability` remains seeded idempotently.
- A mock `POST /agents/tool-calls` can store a `reservation.quote.v0` output.
- No external Resy/OpenTable/Google/phone/payment API is called.

### Slice D — RN/native review surface later

Add UI only after schema/fixtures pass.

Acceptance:

- From a card, user can request “Check availability”.
- UI shows quote/handoff and expiry.
- UI does not book automatically.

## Recommended first PR

Do **Slice A only**, or Slice A + minimal model decode checks if small.

Reason: V0 must stabilize the card primitive first. V1 should document the action/side-effect boundary before any UI/booking behavior exists.

## Out of scope for V1

- Real Resy/OpenTable/SevenRooms integration.
- Browser automation to book a table.
- Payment, deposits, or purchase actions.
- Phone-call agents.
- Merchant-side POS/order fulfillment.
- Jiagon receipt minting.
- Public Yelp-like pages or ranking network.

## Product wording

Internal:

```text
SAV-E remembers places. SLR makes them actionable. Receipts prove what happened.
```

External later:

```text
Agents do not just read reviews — they can check if a trusted recommendation is bookable now.
```
