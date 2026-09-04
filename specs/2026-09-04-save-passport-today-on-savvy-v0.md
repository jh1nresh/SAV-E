# SAV-E Passport Today on Savvy v0

Status: draft product spec. Founder 2026-09-04: implement as a **separate Tim PR** on current `main`. Look stays Atlas kraft / forest / coral / postcard. Do not import RPG / pastel game chrome from the X habit-quest demo. Packet to SAV-E. Do not merge from agents.

## Product brief

- Observed ask: Founder shared an X daily-quest Home (streak, Level/XP, Today’s Quest, gems, Path/Shop/Progress). Asked whether Profile/Passport can use that “任務模式.”
- Classification: **thin Passport strip only**. Borrow checklist structure; do **not** replace Passport with a gamified Home.
- Complements: `specs/2026-08-23-save-one-job-per-tab-v0.md` (Passport job stays identity + stamps + connections + privacy). One Job Per Tab still holds.
- Hard rule unchanged: app may observe a purchase; only the server may grant one. No new commerce loop.

## Placement

On root Passport (`ProfileView` when `isRootTab`):

1. PassportTopBar
2. PassportHero
3. PassportStampSection (existing ledger)
4. **NEW: Today on Savvy** (this spec)
5. Existing control pocket (language / Pro disclosure, Memory, Friends & Lists, sign out, delete)
6. PassportCountingRulesPanel
7. PassportVisibilityPanel

Do not move Friends & Lists into this strip. Do not add a fifth root tab. Do not add Path / Shop / Progress chrome.

## Today on Savvy

Eyebrow: `TODAY ON SAVVY` / `今日 Savvy`  
Subtitle (one line): English `Up to three real next steps` / 繁中 `最多三件真正要做的事`

Show **at most 3** mission rows. Prefer live, incomplete missions only. If none apply, **hide the whole strip** (no empty quest card, no “0/5 completed” RPG header).

### Mission catalog (fixed IDs; product actions only)

| id | When shown | Title (EN / 繁中) | Detail | Primary action |
|----|------------|-------------------|--------|----------------|
| `confirm_waiting_clue` | `waitingClues >= 1` | Confirm a waiting clue / 確認一個待審線索 | Uses existing review queue count | Opens Saves / Review path already used from Home (`onReviewAll` / equivalent Passport can reach). Prefer the same destination Home’s review CTA uses. |
| `share_recommendation` | At least one saved Map Stamp whose visibility is not already the shareable-recommendation state Origin consumes | Share one Map Stamp / 分享一個地圖章推薦 | Fills Origin for peers | Deep-link into existing visibility / share affordance for one eligible place (PassportVisibilityPanel or place share). Prefer first private eligible stamp. |
| `invite_or_follow_friend` | `followedFriends` is empty **or** user has never shared invite (if invite URL available) | Invite or follow a friend / 邀請或追蹤朋友 | Feeds Origin + connections | Opens `PassportConnectionsView` (Friends section). |

Ordering when multiple qualify: `confirm_waiting_clue` → `share_recommendation` → `invite_or_follow_friend`. Cap at 3 (catalog is already ≤3).

### Row chrome

Postcard ticket, not game card:

- Leading: existing perforated medallion / stamp icon (forest / mint / coral), not 3D soap/dumbbell art.
- Title + one muted detail line.
- Trailing: open chevron or coral text button — **not** a dashed RPG checkbox that awards XP.
- Tap runs the primary action. Optional quiet checkmark **after** the underlying product state flips (waiting clue confirmed, place shareable, friend followed). No confetti, no gem burst, no strikethrough quest list animation required for v0.
- Completion removes that row on next render; when catalog empty, strip disappears.

### Forbidden

- XP, Level, gems/diamonds, streak calendar, Path / Shop / Progress tabs
- “Quests reset at midnight” copy
- Pastel blue game shell; Dojo dark glass
- New backend quest table, leaderboard, or reward grant
- Granting Pro / entitlement from completing a mission
- Folding this into Home, Map, Origin, or tab-bar PRs (#183–#186)

## Accept / reject

**Accept:** Passport still reads as a passport; a slim kraft strip under stamps offers 1–3 real Savvy actions; completing them only updates existing counts/visibility/friends; strip hides when idle.

**Reject:** Passport becomes a second Home with streak/XP/Shop; empty quest theater; new currency; fifth tab; shipping without a Tim packet.

## Out of scope

Merge of #183–#186 (founder merges those separately). Origin empty-peers product change beyond linking share. App Store. Railway. Schema. TestFlight upload. Judge unless Elon asks.

## Verification (Tim)

- Source / UI lock: strip absent when `waitingClues == 0` and no share/follow mission applies.
- With `waitingClues >= 1`, first row opens review path; accessibility id e.g. `profile.today.confirmWaitingClue`.
- Share row opens existing visibility/share path; id `profile.today.shareRecommendation`.
- Invite row opens connections Friends; id `profile.today.inviteFriend`.
- No new StoreKit / grant-path symbols in the diff.
- `git diff --check` clean; focused build or source-contract test preferred on Linux agent if Xcode unavailable.
- Simulator: only if needed for UI proof; default build-only.

## Human gates

- Founder asked SAV-E to ticket Tim and open a PR (2026-09-04).
- Tim implements one PR on current `main`. Packet to SAV-E.
- Founder / Elon merge. Do not merge from Tim or SAV-E. Do not assign Judge from this ticket.
