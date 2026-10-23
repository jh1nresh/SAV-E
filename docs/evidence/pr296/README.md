# PR 296 Friends evidence

HoP visual reference is Codex packet spec §7.4 and the Friends column of
the light/dark main mocks. Friends is a **real 0.90 gate** against
`ProductionTargets/friends.png`. Home deferral on #290 does not apply
to Friends. Only user-confirmed Map Stamps are saved place memory.

The PNGs below are still the 9fad61a gallery. Do not treat them as
current-head rasters. Fresh attachments from the next `ios` run land
under artifact `save-atlas-parity-<sha>` → `SAVE-First-Run`. This
directory is not refreshed in this push.

## Section D gallery (simulator XCTAttachments)

Light and dark list, empty (en + zh-Hant), accessibility XXXL, plus
375pt / 430pt letterboxes on the same iPhone 16 Pro (402pt) via
`--uitest-friends-width=375|430`. CI does not boot extra simulators.

F-V1..V4 / F-B2 / F-B3 / F-B7 width attachments on the next `ios` run:

| ID | Attachment |
| --- | --- |
| F-B2 empty en 375 | `friends-empty-en-375` |
| F-B2 empty zh-Hant 430 | `friends-empty-zh-Hant-430` |
| F-V populated 375 / F-B7 last-at | `friends-town-375` |
| F-V populated 430 / F-B7 last-at | `friends-town-430` |
| F-B3 loading 375 | `friends-loading-375` |
| F-B3 error 430 | `friends-error-430` |
| a11y large text | `friends-dynamic-type-xxxl` (already on the 402pt rail) |

| Light list | Dark list |
| --- | --- |
| <img alt="light Friends" src="light-friends.png" width="240" /> | <img alt="dark Friends" src="dark-friends.png" width="240" /> |

| Empty (en) | Empty (zh-Hant) |
| --- | --- |
| <img alt="empty Friends English" src="friends-empty-en.png" width="240" /> | <img alt="empty Friends Traditional Chinese" src="friends-empty-zh-Hant.png" width="240" /> |

Parity mask (Home only; Friends has none):

<img alt="home-mask white=ignore" src="home-mask.png" width="240" />

## Provenance

These PNGs are real iOS Simulator XCTAttachments from the macOS `ios`
workflow, iPhone 16 Pro (402pt logical width), exported from
`xcresulttool` via `SAVE-First-Run/manifest.json`.

| File | Attachment name | Source |
| --- | --- | --- |
| `light-friends.png` | `light-friends` | run [39536918772](https://github.com/jh1nresh/SAV-E/actions/runs/39536918772), head `9fad61a` |
| `dark-friends.png` | `dark-friends` | same |
| `five-tab-friends.png` | `five-tab-friends` | same |
| `friends-empty.png` | `five-tab-friends-coming-soon` | same |
| `friends-empty-en.png` | `friends-coming-soon-en` | same |
| `friends-empty-zh-Hant.png` | `friends-coming-soon-zh-Hant` | same |
| `friends-en.png` | `friends-after-opening-en` | same |
| `friends-zh-Hant.png` | `friends-after-opening-zh-Hant` | same |
| `home-mask.png` | Home parity mask | `Prototypes/AtlasPostcard/Reference/ProductionTargets/home-mask.png` |

Friends has no ignore-mask. `home-mask.png` is the only production mask
(white = ignore) and is attached so the packet review can see the Home
gate is unchanged (founder 2026-10-22). The Friends 0.90 compare uses
`five-tab-friends` against `ProductionTargets/friends.png` with no
REVIEW conversion.

The Friends chrome in those rasters is the pre-P0 filled-sticker build.
The current head redraws stickers as 32pt ink outlines, thins the avatar
ring and Invite stroke, and **gates Friends at 0.90**. Fresh
`light-friends` / `dark-friends` / `friends-empty-*` /
`friends-dynamic-type-xxxl` / `friends-loading` / `friends-error` /
`friends-empty-en-375` / `friends-empty-zh-Hant-430` /
`friends-town-375` / `friends-town-430` / `friends-loading-375` /
`friends-error-430` attachments land on the next `ios` run under
artifact `save-atlas-parity-<sha>` → `SAVE-First-Run`.

## Side-by-side vs packet §7.4 Friends column

Packet / main-mock column (from HoP + DESIGN 2026-10-21): people-first
list, Caveat/Iansui title, outline Invite, forest-ring avatars, last-at
rows, 32pt line-art stickers, no shared map, no animation (F-B11).

| Topic | Packet / mock | 9fad61a simulator rasters | Current head (code) |
| --- | --- | --- | --- |
| P0 stickers | 32pt outline line-art | Filled postage boxes (kraft/gold/red/green) | 32pt official outlines coffee / noodle / temple / lantern |
| P1 avatar ring | Packet forest ring | 2.4pt wobbly ink ring | 1.5pt circle stroke |
| P1 Invite | Outline chip | 1.5pt capsule | 1pt capsule, label = Invite / 邀請 |
| P1 Kai sticker | Official temple outline | Filled red lantern in a box | Official `.temple` (v2 lantern not adopted) |
| P1 tab bar | Shared Atlas root bar | Home / Map / + / Friends / Passport | Unchanged shared chrome (not a Friends-only file) |
| P2 background | Dotted paper | `SaveDottedBackground` (dots read faint at 1×) | Same |
| P2 fixture text | last at Place · 2d | Mia / Leo / Kai / Ana last-at copy | Same isolated `--uitest-friends-town` fixture |
| Empty (F-B2) | Empty + Find friends | `friends-empty*.png` | Same + zh-Hant + 375/430 letterbox |
| Loading / error (F-B3) | Must be shown | Not in 9fad61a set | `friends-loading` / `friends-error` + 375/430 |
| Animation (F-B11) | None | None | None (`SaveFriendsView` has no `withAnimation`) |
| 375 / 430 | Requested | Not captured | Letterboxed on the 402pt device via `--uitest-friends-width` |

Invite / 邀請 opens Passport connections, Friends section:
`SaveFriendsView.onConnections` → `ContentView` sets
`requestsSocialConnections` and selects the Passport tab →
`ProfileView.requestsConnections` presents `PassportConnectionsView`.
