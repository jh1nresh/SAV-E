# Agent-Callable Memory Contract

> Last updated: 2026-05-14

## Goal

Make SAV-E's memory usable by agents instead of only by app screens:

```text
SAV-E
-> calls R8 taste/ranking capabilities
-> calls SLR seller-side availability/quote capabilities
-> stores tool-call trace
-> returns reviewable recommendation sets
```

This turns SAV-E from a saved-place app into an orchestration agent that can ask other agents for ranked recommendations and seller-side availability without executing bookings in this patch.

## Agent Families

- `R8`: review, rating, taste, and preference-memory agents.
- `SLR`: seller-side agents. Product copy may say `SLL-R`, but backend data uses canonical `SLR`.
- `BYR`: buyer-side agents.
- `NEG`: negotiator agents.
- `VFY`: verifier agents.

## Product Contract

SAV-E should expose memory through four backend concepts:

- `agent_capabilities`: callable actions such as `R8.rank_places` and `SLR.restaurants.search_availability`.
- `agent_tool_calls`: user-scoped trace of SAV-E calling a capability, including input, output, status, and linked capture/recommendation.
- `recommendation_sets`: a grouped answer to a user prompt, optionally linked to a raw capture.
- `recommendation_items`: ranked options inside a recommendation set, optionally linked to a place candidate or saved place.

The first seeded capabilities are mock contracts only:

- `R8.rank_places`
- `R8.explain_match`
- `SLR.restaurants.search_availability`
- `SLR.flights.search_itineraries`

## API Contract

- `GET /agents/capabilities`
- `GET /agents/tool-calls`
- `POST /agents/tool-calls`
- `GET /memory/recommendations`
- `POST /memory/recommendations`
- `GET /memory/recommendations/:id`
- `PATCH /memory/recommendations/:id`

`POST /memory/recommendations` accepts an optional `items` array and creates the set plus items transactionally.

All user-owned routes are scoped through the same Privy/guest auth path as the rest of the Railway backend.

## Out of Scope

- No iOS UI in this patch.
- No real R8 or SLR execution in this patch.
- No booking, reservation, payment, or SLL-R purchase flow.
- No external flight, restaurant, Resy, OpenTable, airline, or payment API calls.
- No automatic write to Saved Places from recommendations.

## Acceptance Criteria

- Database schema includes capability registry, tool-call traces, recommendation sets, and recommendation items.
- Seed capabilities are inserted idempotently.
- Backend exposes capability, tool-call, and recommendation endpoints.
- Recommendation items can reference captures, candidates, and saved places only through user-scoped validation.
- TypeScript backend build passes.
- Existing native iOS build still passes.
