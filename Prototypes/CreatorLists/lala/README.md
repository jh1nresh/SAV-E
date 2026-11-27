# 拉拉熊清單：Savvy 本地接入

Frozen upstream: [2xin15/lala-food at 239f2a0](https://github.com/2xin15/lala-food/tree/239f2a049cb94a9526cc6c06cd37e2a5f3bfaa21), updated 2026-11-27. Creator: `zeke_6973`; list compiler: `2xin15__`.

## Coverage

| Item | Count |
| --- | ---: |
| Creator wants to go | 248 |
| Creator visited | 74 |
| In both lists | 42 |
| Unique places | 280 |
| Attached to existing Savvy/map identity | 91 |
| Distinct places added by creator CID | 189 |
| Unresolved mappings | 0 |
| Places with supplied Threads references | 41 |
| Threads/place associations | 44 |
| Distinct Threads URLs | 36 |

The original shared post's 245/73 counts predate this snapshot. A list entry does
not imply a Threads post exists. The 44 associations are the curator's indexed
references, not a complete crawl of the creator's account. Text is a transcription
from that repository, not freshly retrieved/verified platform content. No photos
are inferred or borrowed, and there is no change to personal Saved/visited state.

`reviewed-branches.json` records the 57 formerly pending decisions (47 existing,
10 distinct) plus three prior decisions. Decisions pin source/target names and
addresses, evidence URLs and reasoning. Distinct-place reviews explicitly reject
the whole candidate set; an input change invalidates that decision. The only
extended distance case is the named 自由廣場 area, not its separate gate.
Branch identity matching is not certification of current opening hours/operation.

Examples:

- 十一香景美店 -> `poi/node/4033359736`, 3 source references. Reuses the named
  restaurant instead of the different 創意鍋麵 candidate at the same address.
- Mo-Mo 復興牧場 -> `poi/node/6354698707`. Official branch address resolves the
  old 42/44 discrepancy; does not merge the nearby 路易莎.
- 林振櫂燒麻糬 -> `savvy/apple_maps/H2710I3F9AE050E2C28`. Keeps the existing
  native shop identity, not the surrounding 寧夏夜市.
- 興波 Diamond Towers -> own creator CID. A cafe tenant is not 新光三越.
- 迷客夏忠孝復興店 -> own creator CID. The misleading existing `忠孝復興店`
  candidate has OSM English name Dreamers Coffee Roasters and a different number.

## Local activation

Debug builds automatically include this checked-in catalog. No import button or
environment setting is required. For an optional task-local replacement, set:

```sh
export SAVVY_LOCAL_CREATOR_SOURCES="$PWD/Prototypes/CreatorLists/lala/CreatorPlaceSources.json"
```

The existing Pocket City packaging phase copies it to `PocketCity/CreatorPlaceSources.json`.
Release excludes both the default catalog and any environment override, and removes
a stale Debug catalog.
The existing expiring public-source snapshot remains independently governed.
No production/backend data is changed by this import.

Consumers:

- Pocket City merges canonical IDs into `loadCityPlaces()` once; native-only
  known identities are materialized using their existing ID, not a second CID.
- Creator-added points remain selectable at street zoom. The live-source layer
  excludes the same IDs. Native Saved/shared pins cover their matching atlas pin.
- Native map drawer and Saved detail show creator membership and supplied text /
  original links, independently of personal notes. Existing photos and selection
  motion are untouched.

## Verification and limitations

Checks run locally:

```sh
python3 -B -m unittest discover -s Tests/ci -p 'test_lala_creator_import.py' -v
node --test Prototypes/TaipeiPocketCity/tools/creator-place-sources.test.mjs Prototypes/TaipeiPocketCity/tools/ios-map.test.mjs
python3 -B scripts/test-package-pocket-city.py PocketCityPackageTests.test_stage_updates_removes_stale_and_recovers_from_interruption
```

Real city replay: 39,750 base places -> 39,952 map places, all 280 creator entries
reachable, zero duplicate IDs, repeated append unchanged. The 202 added map
features comprise 189 new identities and 13 existing native-only identities.
Host Swift model check decoded all 280 entries, matched exact branches/aliases
and rejected 280 wrong-location variants; Swift parsing passed. These are not
native UI or full Xcode type-check evidence.

Current task receipts and deterministic regeneration command:
`/Users/jhinresh/.codex/worktrees/savvy-lala-creator-local-evidence/`.
`CreatorPlaceSources.json` contains input SHA256 hashes. Raw inputs are not
executed; the importer accepts only JSON literal assignments.

The initial local verification did not include iOS build/runtime. Independent
review is pending because this parent task exceeds the workflow's agent lifecycle
budget. The PR is a Draft until required native verification, CI and independent
review pass. Phone installation is separately authorized; its result is recorded
in the task handoff. No production data or Release catalog is changed.
