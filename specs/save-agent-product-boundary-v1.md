# SAV-E App and Agent Product Boundary V1

> Last updated: 2026-05-20
> Status: proposed product boundary

## PM Gate

Title: Define SAV-E app and agent product boundary

Repo: `/Users/jhinresh/wanderly`

Problem: SAV-E is currently pulled between two shapes: a polished consumer iOS app and an agent-native workflow/memory product. Without a clear boundary, UI polish risks turning SAV-E into a generic travel bookmark app, while agent work risks becoming invisible to normal users.

Goal: Define one product architecture where the iOS app and SAV-E agent advance in parallel while sharing the same memory, save-card, candidate, trip, and action substrate.

Acceptance criteria:

- Distinguish what belongs in the iOS app, what belongs in the SAV-E agent, and what belongs in shared backend/memory.
- Preserve the agent-first thesis in product wording and UI direction.
- Define what the next UI polish PR should optimize for.
- Define what the next agent/backend PR should expose.
- Keep booking, payments, and external platform automation out of scope until user confirmation and tool-call contracts exist.

Verification:

- Spec is written in `specs/`.
- Spec is mirrored to `~/brain/wiki/projects/wanderly/`.
- `git diff --check` passes.

Risk:

- If this boundary is too vague, future PRs will drift into collection-first UX.
- If this boundary is too strict, the app may feel unfinished for friends using TestFlight.

Out of scope:

- No UI implementation in this spec.
- No backend schema migration in this spec.
- No App Store metadata changes.
- No real booking, payment, restaurant, flight, or third-party agent execution.

Do not touch:

- Signing settings.
- TestFlight build numbers.
- Live Railway/Vercel production variables.
- App Clip configuration.

Suggested labels: `product`, `spec`, `ios`, `agent`

Owner: JhiNResH

Follow-up worker: iOS/frontend worker for UI polish, backend/agent worker for callable contract work.

## Product Decision

SAV-E should be both:

- a consumer-facing app that normal users can open, understand, and trust;
- an agent users and other agents can call to investigate, remember, and act on travel/place signals.

These are not two separate products. They are two entry points into the same system:

```text
User / Siri / Share Extension / Web / Dojo / SLL-R
-> SAV-E Agent
-> Memory Layer / Review Candidates / Save Cards / Trips / Actions
-> iOS App / Web Preview / Agent Response
```

The app is the human control surface. The agent is the workflow engine. The memory layer is the source of truth.

## Core Thesis

SAV-E is not primarily a Roamy-style collection app. SAV-E is an agent-first place memory product:

```text
Give SAV-E any place signal.
SAV-E investigates first.
SAV-E asks before saving.
SAV-E remembers in agent-readable form.
SAV-E helps the user act later.
```

External wording:

```text
SAV-E is your personal place agent. Send it links, posts, screenshots, notes, or map URLs; it investigates the real place, remembers the evidence, and helps you plan or act.
```

Internal wording:

```text
SAV-E is the agent-readable memory and action layer for places.
```

## Boundary: iOS App

The iOS app owns the user-facing experience:

- sign-in and account state;
- map and saved places;
- review candidates;
- trip planner and trip preview;
- share extension handoff;
- Google Takeout / file import flows;
- profile and user settings;
- notification/permission prompts;
- local vault visibility;
- polished mobile UI states.

The app should optimize for:

- clear first-run comprehension;
- fast saving from share sheet;
- obvious review-before-save behavior;
- strong empty states;
- one-handed mobile ergonomics;
- reliable back/close navigation;
- no fake coordinates;
- no hidden pending queues;
- graceful offline/local fallback.

The app should not own:

- long-running investigation logic;
- cross-source evidence ranking;
- external booking execution;
- agent-to-agent orchestration;
- memory schema decisions.

## Boundary: SAV-E Agent

The SAV-E agent owns workflows:

- investigate public link metadata;
- investigate user-provided screenshot/video evidence;
- convert social handles/captions into review candidates;
- decide whether a signal is source-only, review candidate, confirmed place, trip input, or action quote;
- ask follow-up questions when evidence is weak;
- call R8-style preference/ranking capabilities;
- call SLR/SLL-R-style seller-side quote or availability capabilities;
- generate `save.card.v0` artifacts;
- return action proposals, not hidden side effects.

The agent should optimize for:

- evidence-backed answers;
- explicit uncertainty;
- reviewable candidates before saved places;
- tool-call traces;
- user confirmation before side effects;
- agent-readable outputs.

The agent should not:

- auto-save uncertain social links as confirmed places;
- invent coordinates;
- auto-book restaurants or flights;
- call payment APIs;
- depend on one mobile screen to be useful.

## Boundary: Shared Memory and Backend

The shared substrate owns durable state:

- raw captures;
- place candidates;
- agent decisions;
- saved places;
- trips;
- recommendation sets;
- agent capabilities;
- agent tool-call traces;
- `save.card.v0` artifacts;
- future action quotes and receipts.

The backend/memory layer should be callable by:

- native iOS;
- RN/web;
- share extension;
- App Intents/Siri;
- Dojo or other agent registries;
- future SLL-R/R8 integrations.

The backend/memory layer should keep these states separate:

```text
source_only
review_candidate
confirmed_place
trip_input
action_quote
action_receipt
```

Do not collapse `review_candidate` into `confirmed_place` just because a UI wants to show a pin.

## UX Direction For Next iOS Polish

The next iOS polish PR should make the app feel like the control surface for an agent.

Priorities:

1. Login/onboarding should explain SAV-E in one sentence, not generic travel copy.
2. The primary input should stay conversational: `Ask SAV-E about your places...`.
3. Add Spots should feel like agent commands, not static categories.
4. Review candidates should look like SAV-E's output queue.
5. Saved places should feel confirmed and stable.
6. Trips should feel like composed memory, not a separate fake demo.
7. Profile should only expose useful account/memory controls.
8. Every modal/sheet must have a visible escape path.

Recommended first-screen copy:

```text
SAV-E
Your personal place agent.
Send links, posts, screenshots, notes, or maps. SAV-E investigates first, then asks before saving.
```

Recommended command surface:

- `Investigate a link`
- `Import from clipboard`
- `Review candidates`
- `Plan from saved places`
- `Investigate media evidence`
- `Ask about my places`

## Agent Direction For Next Workflow PR

The next agent/backend PR should not start with UI. It should expose the callable contract:

- `POST /agent/investigate-link`
- `POST /agent/investigate-media`
- `POST /agent/plan-trip`
- `POST /agent/propose-action`
- `GET /agent/tool-calls`

Each response should include:

- human summary;
- candidate places;
- evidence;
- confidence;
- missing information;
- suggested next action;
- `save.card.v0` projection when applicable;
- tool-call trace id when applicable.

The first implementation may be mock-backed or route to existing memory/candidate services, but it should preserve the contract.

## App And Agent Interaction Examples

### Instagram Reel

```text
User shares IG Reel to SAV-E
-> share extension stores raw capture
-> SAV-E agent reads metadata/caption
-> agent creates review candidates with evidence
-> app shows candidates in Review
-> user confirms one place
-> memory records agent_decision=saved_place
```

### Screenshot Or Video

```text
User uploads screenshot/video
-> SAV-E agent extracts visible clues
-> agent proposes candidate places
-> uncertain candidates stay in Review
-> no coordinates are saved until map refinement succeeds
```

### Restaurant Action

```text
User asks: book a dinner near my saved Tokyo places
-> SAV-E calls R8 to rank preferences
-> SAV-E calls SLR restaurants for availability quote
-> SAV-E returns action_quote
-> user confirms outside this spec
```

No booking is executed in this boundary spec.

## Success Criteria

SAV-E is moving in the right direction when:

- friends can use the app without understanding agent infrastructure;
- power users can call SAV-E as an agent without opening the app;
- uncertain places land in Review, not Saved Places;
- every saved place has a defensible source/evidence trail;
- the same memory can power map UI, trip planning, Siri, Dojo listing, and future SLL-R calls.

## Anti-Goals

- Do not clone Roamy as a collection-first map app.
- Do not bury the agent behind static cards.
- Do not make the app depend on fake demo data.
- Do not expose dangerous actions without explicit user confirmation.
- Do not let App Clip, TestFlight, or App Store constraints define the core product primitive.

## Suggested Implementation Order

1. Polish iOS app as the human control surface.
2. Add explicit agent investigation endpoints or local service boundaries.
3. Render Review candidates as the visible agent output queue.
4. Make `save.card.v0` export/import visible from app and agent workflows.
5. Add R8/SLR recommendation and quote traces behind clear user confirmation.
6. Only then expand App Clip and public trip links around the same memory/card standard.
