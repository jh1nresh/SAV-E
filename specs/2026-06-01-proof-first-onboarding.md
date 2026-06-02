# Proof-First Onboarding

> Last updated: 2026-06-01

## Product Decision

SAV-E onboarding should not start as a preference quiz.

New users need to see proof that SAV-E can turn one messy place signal into a
trusted private place memory:

```text
messy saved place
-> Review Candidate / Source Clue
-> confirmed Map Stamp
-> Ask from my saved places
```

Preference chips are useful only after the first proof. They should tag why the
user saved the place, not ask abstract personality questions before SAV-E has
earned trust.

## Problem

The current onboarding explains the product in four swipe pages:

- save places from anywhere;
- review uncertain finds;
- build a private map;
- ask before deciding.

The copy is directionally correct, but it is still an explainer. A new user can
finish onboarding without understanding what to do first or why SAV-E is
different from Google Maps, Roamy, or a generic AI travel app.

## Goal

Replace the explainer with a proof-first interactive setup that teaches the core
loop in under 60 seconds:

1. enter or sample one real messy place clue;
2. see what SAV-E found and what is still missing;
3. confirm it into a Map Stamp;
4. ask SAV-E from saved memory;
5. optionally tag why the place matters.

## Acceptance Criteria

- First screen asks for one messy place clue, not user preferences.
- User can tap a sample clue if they do not want to type.
- The onboarding surface visibly progresses through:
  - `Clue`;
  - `Review Candidate`;
  - `Map Stamp`;
  - `Ask`;
  - optional intent tags.
- `Review Candidate` explains found source/name and missing address/coordinates.
- `Map Stamp` state clearly says the place is confirmed only after user action.
- The final CTA exits onboarding into the app.
- `Skip for now` remains available.
- Copy is localized for English and Traditional Chinese.
- No parser, auth, backend, paywall, TestFlight, or data-model changes.

## Out Of Scope

- Live parsing during onboarding.
- Persisting onboarding preference chips.
- Hard paywall.
- Full import hub redesign.
- New App Store screenshots.
- Changes to share extension parsing.

## Verification

- `git diff --check`
- Xcode simulator build:

```bash
xcodebuild build -quiet -project SAV-E.xcodeproj -scheme SAV-E \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

