# SAV-E Passport Today on Savvy v0

Status: implementation brief
Complements: `DESIGN.md` Passport rules, `specs/2026-08-23-save-one-job-per-tab-v0.md`
Palette: production `SaveAtlasPalette` — Atlas kraft / forest / coral / postcard.
Do not import RPG / pastel game chrome.

Cited by `SAV-E/Views/Profile/ProfileView.swift` and
`Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift`.

## Paid user job / observed failure

A traveler opens Passport to confirm identity, stamps, connections, and
privacy. They still need a short list of real next steps — confirm a waiting
clue, share one Map Stamp, invite or follow a friend — without turning
Passport into a quest board or a fifth root tab.

Observed failure: root Passport is a ledger plus a control pocket. The next
action lives on Home, Saves, or Friends & Lists, so the traveler has to guess
where to go.

## Acceptance criteria

1. Root Passport (`ProfileView` when `isRootTab`) order is exactly:
   1. PassportTopBar
   2. PassportHero
   3. PassportStampSection (existing ledger)
   4. Today on Savvy (this packet)
   5. Existing control pocket (language / Pro disclosure, Memory, Friends & Lists, sign out, delete)
   6. PassportCountingRulesPanel
   7. PassportVisibilityPanel
2. Do not move Friends & Lists into this strip. No fifth root tab. No Path /
   Shop / Progress chrome.
3. Eyebrow: `TODAY ON SAVVY` / `今日 Savvy`.
   Subtitle: EN `Up to three real next steps` / 繁中 `最多三件真正要做的事`.
4. Show at most 3 mission rows. Live incomplete only. If none apply, hide the
   whole strip (no empty quest card).
5. Mission catalog (fixed IDs), order confirm → share → invite:

   | id | When shown | Title EN / 繁中 | Action |
   |----|------------|----------------|--------|
   | `confirm_waiting_clue` | waitingClues >= 1 | Confirm a waiting clue / 確認一個待審線索 | Same review destination Home’s review CTA uses (`onReviewAll` / equivalent Passport can reach) |
   | `share_recommendation` | ≥1 saved Map Stamp not already in shareable-recommendation state Origin consumes | Share one Map Stamp / 分享一個地圖章推薦 | Existing visibility/share affordance; prefer first private eligible stamp |
   | `invite_or_follow_friend` | followedFriends empty OR never shared invite | Invite or follow a friend / 邀請或追蹤朋友 | Opens PassportConnectionsView Friends section |
6. Row chrome: postcard ticket — perforated medallion/stamp icon
   (forest/mint/coral), title + muted detail, trailing chevron or coral text.
   Not a dashed RPG checkbox or XP. Tap = primary action. Quiet checkmark only
   after underlying state flips. No confetti/gems/strikethrough required.
7. Accessibility ids: `profile.today.confirmWaitingClue`,
   `profile.today.shareRecommendation`, `profile.today.inviteFriend`.
8. Hard rule: the app may observe a purchase; only the server may grant one.
   No new commerce loop. Missions do not grant Pro.
9. One Job Per Tab: Passport stays identity + stamps + connections + privacy.

Failure fixtures:

- Strip visible when waitingClues == 0 and no share/follow mission applies.
- Empty quest card, XP / Level / gems / streak calendar, or Path / Shop /
  Progress chrome.
- Friends & Lists folded into the strip.
- New StoreKit / grant-path symbols (`SaveEntitlementStore`,
  `serverVerifiedTier ?? locallyObservedTier`, `SaveStoreKitService`).

## Classification

Feature. Standard lane. Passport IA only.

## Demand, pricing, first distribution

- Demand proof: founder lock 2026-09-04 (Elon). Separate PR off current
  `main`. Do not stack on #184 / #185 / #186.
- Pricing / paywall hypothesis: core place memory stays free. Passport may
  disclose Pro behind the existing control-pocket disclosure. Today on Savvy
  does not sell, grant, or unlock Pro.
- First distribution: draft PR against main. No merge, no Judge, no
  TestFlight, no App Store Connect, no Railway / Vercel.

## Files and systems in scope

- `SAV-E/Models/UserProfile.swift` (catalog + local invite-share flag)
- `SAV-E/Views/Profile/ProfileView.swift`
- `SAV-E/App/ContentView.swift` (`onReviewAll` wiring only)
- `DESIGN.md` (Today on Savvy noun + Passport rule)
- `Tests/SocialPlacePipelineTests/SaveSearchControllerTests.swift`
- `Tests/SocialPlacePipelineTests/AtlasOneJobPerTabUITests.swift`
- `scripts/check-passport-today-on-savvy.py`

Out of scope: StoreKit products and prices, entitlement enforcement, schema,
Railway, App Store listing, Map / Home / Origin restyles, #183–#186, XP,
leaderboards, midnight quest reset, granting Pro from missions.

## Verification

- Strip absent when waitingClues == 0 and no share/follow mission applies.
- Accessibility ids present in source.
- No new StoreKit / grant-path symbols in the diff.
- `git diff --check` clean.
- Focused catalog tests (XCTest) plus Linux-safe source check script.
- CI kicked after the PR opens.

iOS compile stays on the generic simulator destination. Do not boot a
simulator for this packet.

## Security and privacy

- Invite-share flag is a local UserDefaults boolean. It is not a grant path.
- Share action reuses the existing visibility / share affordance. Private
  notes stay private.
- No new auth, payment, or schema.

## Actions that still require human approval

- Judge
- Founder merge
- TestFlight / App Store Connect
- Railway / Vercel
- Production secrets or schema changes

# SAV-E Passport Today on Savvy v0

Look: Atlas kraft / forest / coral / postcard. Do NOT import RPG / pastel game chrome.
Hard rule: app may observe a purchase; only the server may grant one. No new commerce loop.
One Job Per Tab: Passport stays identity + stamps + connections + privacy.

### Placement on root Passport (`ProfileView` when `isRootTab`)
1. PassportTopBar
2. PassportHero
3. PassportStampSection (existing ledger)
4. **NEW: Today on Savvy** (this PR)
5. Existing control pocket (language / Pro disclosure, Memory, Friends & Lists, sign out, delete)
6. PassportCountingRulesPanel
7. PassportVisibilityPanel

Do not move Friends & Lists into this strip. No fifth root tab. No Path / Shop / Progress chrome.

### Today on Savvy
Eyebrow: `TODAY ON SAVVY` / `今日 Savvy`
Subtitle: EN `Up to three real next steps` / 繁中 `最多三件真正要做的事`
Show at most 3 mission rows. Live incomplete only. If none apply, **hide the whole strip** (no empty quest card).

Mission catalog (fixed IDs):
| id | When shown | Title EN / 繁中 | Action |
|----|------------|----------------|--------|
| `confirm_waiting_clue` | waitingClues >= 1 | Confirm a waiting clue / 確認一個待審線索 | Same review destination Home’s review CTA uses (`onReviewAll` / equivalent Passport can reach) |
| `share_recommendation` | ≥1 saved Map Stamp not already in shareable-recommendation state Origin consumes | Share one Map Stamp / 分享一個地圖章推薦 | Existing visibility/share affordance; prefer first private eligible stamp |
| `invite_or_follow_friend` | followedFriends empty OR never shared invite | Invite or follow a friend / 邀請或追蹤朋友 | Opens PassportConnectionsView Friends section |

Order: confirm → share → invite. Cap 3.

Row chrome: postcard ticket — perforated medallion/stamp icon (forest/mint/coral), title + muted detail, trailing chevron or coral text (NOT dashed RPG checkbox / XP). Tap = primary action. Quiet checkmark only after underlying state flips. No confetti/gems/strikethrough required.

### Forbidden
XP, Level, gems, streak calendar, Path/Shop/Progress, midnight quest reset copy, pastel game shell, new quest backend/leaderboard/reward grant, granting Pro from missions, folding into #183–#186.

### Verification
- Strip absent when waitingClues==0 and no share/follow mission applies.
- Accessibility ids: `profile.today.confirmWaitingClue`, `profile.today.shareRecommendation`, `profile.today.inviteFriend`.
- No new StoreKit / grant-path symbols in the diff.
- Prefer adding `specs/2026-09-04-save-passport-today-on-savvy-v0.md` with this spec text.
- `git diff --check` clean; focused tests if feasible on Linux; CI kicked.

### Done when
Open PR against main with CI kicked. Return: PR URL, HEAD SHA, CI run URL if known, files touched, residual risk, confirmation no XP/Shop/grant-path.
