# PR 296 Friends evidence

HoP visual reference is Codex packet spec §7.4. Friends is a
**real 0.90 gate** against `ProductionTargets/friends.png`
(md5 `fb72c859`). No Friends mask. Threshold, mask, and target
bytes are unchanged. Home deferral on #290 does not apply to
Friends. Only user-confirmed Map Stamps are saved place memory.

The PNGs below are still the 9fad61a gallery. Do not treat them as
current-head rasters. Fresh attachments from the next `ios` run land
under artifact `save-atlas-parity-<sha>` → `SAVE-First-Run`.

## Width shots (real simulators)

HoP requires 375 (SE/mini), 390, and 430 (Pro Max) on real devices
with width and column assertions on the same head. 402pt letterboxing
is gone. `ios.yml` boots:

- 375: iPhone-SE-3rd-generation
- 390: iPhone-14 (not iPhone 16 @ 393)
- 430: iPhone-16-Pro-Max

Attachments: `friends-375` / `friends-390` / `friends-430` plus
`friends-town-<width>`. Column value is `1` (people-first list).

## Side-by-side vs packet §7.4 / `friends.png`

| Topic | Target | Current head |
| --- | --- | --- |
| Title | 34pt Caveat / Iansui | 34pt locked `SaveDisplayTitle` |
| Invite | Small outline chip | 12pt / 28pt min height outline |
| Avatars | 48pt forest rings | 48pt, 2.5pt forest stroke, 24pt initials |
| Stickers | coffee / noodle / lantern / hill | 32pt; outlined if saved, colored if visited |
| Rows | ~57pt, four rows near y≈300 | minHeight 57, tight vertical pad |
| Map | Hidden | Hidden |
| Animation (F-B11) | None | None |
| Coming-soon | Cannot occur | Deleted; empty feed stays |
| 375 / 390 / 430 | Real devices | real 375 / 390 / 430 |

## Out-of-scope files that stay

`origin/main...#296` is 114 paths because Friends still sits on the
Doodle Home stack. Files beyond #290's file list that belong here:

| File | Why it stays |
| --- | --- |
| `SaveFriendsView.swift` | Friends surface |
| `SharedPostsStore.swift` | Town / loading / error fixtures |
| `SaveDoodleFriendsTests.swift` | Friends locks |
| `ProductionTargets/friends.png` | Locked 0.90 target |
| `ProductionTargets/friends-dark.png` | Dark DESIGN comparison |
| `docs/evidence/pr296/*` | This packet |

Inherited Home/Doodle files (sticker assets, `SaveDoodleHomeView`,
`SaveDisplayTitle`, `ContentView`, `ios.yml`, Home tests) stay because
Friends compiles against those types and the five-tab rail. Removing
them does not compile. They are not a silent #290 merge; #290 is not
merged from this PR.

`home-mask.png` stays so the Home 0.90 compare on this stacked branch
keeps its ignore mask. Friends itself has no mask.
