# AGENTS — SAV-E backend

## The one rule that matters: the memory-quality loop

SAV-E gets better by turning every real user correction into a permanent
regression test. That loop is our moat, not any single answer.

**Rule:** when a user reports a SAV-E bot bug — a screenshot complaint, "wrong
place", "it forgot what I said", "too vague", "saved as a place not a receipt",
etc. — add a FAILING test to `src/sendblueBot.test.ts` that reproduces it
*before* you fix it. The bug is fixed when that test passes and the full suite is
green. No correction ships without its regression test.

`src/sendblueBot.test.ts` **is** the loop-case fixture pack. Many of its cases
come straight from real iMessage screenshots (location re-ask, follow-up
grounding on the recommended place, Toast/Square receipt links, review-after-
restart durability, save-then-"where-is-it", multi-digit order headers, …). Keep
it that way; don't delete a case without a documented reason.

Fixtures use anonymized data only — fake numbers like `+1555…`, no real phones,
receipts, or private notes.

This is the lightweight, already-in-practice version of
`~/brain/wiki/projects/wanderly/save-loop-engineering-memory-quality-spec.md`.
The heavier `loop_cases` tables and capture/triage/patch/judge workers in that
spec are **deferred until real-user scale justifies them** — do NOT build that
internal platform for a bot with ~0 external users.

## Build / test

- `npm run build` — tsc, must have no errors.
- `npm test` — node --test. On Node 18, after a build, run
  `node --test dist/**/*.test.js` (the npm glob needs Node 21+).
- Deploy: `railway up --service wanderly-api --detach` (Railway project `wanderly`).
