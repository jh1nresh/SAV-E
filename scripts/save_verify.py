#!/usr/bin/env python3
"""Deterministic Savvy verification (HoP V1–V8). Linux seed/check; no macOS job.

Commands:
  ./verify seed <seed>
  ./verify run <flow>
  ./verify screenshot <page>
  ./verify check

A flow whose dependency PR is not in this checkout returns SKIP, never PASS.
V5 paywall and V7 App Clip cap (mockup 15) must assert the copy 「已存 50 個」.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

TOOL = "verify"
CLOCK = "2026-10-21T00:00:00+00:00"
LOCALE = "en_US_POSIX"
LANGUAGE = "en"
LOCATION = {
    "label": "Taipei Xinyi",
    "latitude": 25.0330,
    "longitude": 121.5654,
}
FREE_SAVED_PLACE_LIMIT = 50
SAVED_50_COPY = "已存 50 個"
USAGE = [
    "./verify seed <seed>",
    "./verify run <flow>",
    "./verify screenshot <page>",
    "./verify check",
]
SWIFT_ROOTS = (
    Path("SAV-E"),
    Path("SAV-EClip"),
    Path("SAV-EShared"),
    Path("backend/src"),
)

# HoP 2026-10-22 id 定名. Paywall = #295 set; retry = paywall.retry.
FINAL_IDS = {
    "ai.quotaExhausted": "ai.quotaExhausted",
    "home.saves": "home.saves",
    "map.card.beenHere": "map.card.beenHere",
    "passport.root": "passport.root",
    "paywall.benefit.unlimited": "paywall.benefit.unlimited",
    "paywall.retry": "paywall.retry",
    "paywall.savedNote": "paywall.savedNote",
    "saves.unplaced": "saves.unplaced",
    "saves.unplaced.row": "saves.unplaced.row.",
}

# Source probes: a PR is "on this tree" only when every token is present.
PR_PROBES = {
    290: ("home.miniMap", "home.placeList", "home.collected"),
    293: ("freeSavedPlaceLimit",),
    295: (
        "paywall.benefit.unlimited",
        "paywall.savedNote",
        "paywall.retry",
    ),
    296: ("friends.list", "friends.loading"),
    297: ("passport.root",),
    298: ("SaveDoodleMapView",),
    304: ("map.card.beenHere",),
    307: ("clip.pending", "app.handoff.confirmList", "clip.skoverlay"),
    308: (),
}

FLOW_DEPS = {
    "V1": (295,),
    "V2": (290,),
    "V3": (298, 304),
    "V4": (297, 298, 304),
    "V5": (293, 295),
    "V6": (),
    "V7": (307,),
    "V8": (296,),
}

FLOW_SEEDS = {
    "V1": ("empty-free",),
    "V2": ("taipei-12", "empty-free"),
    "V3": ("taipei-12",),
    "V4": ("taipei-12",),
    "V5": ("free-49", "free-50", "pro-50", "ai-exhausted"),
    "V6": ("offline-taipei-12",),
    "V7": ("clip-new", "clip-free-49", "clip-free-50", "clip-dup", "clip-free-47"),
    "V8": ("friends-f1", "friends-none"),
}

SEEDS = (
    "empty-free",
    "taipei-12",
    "free-49",
    "free-50",
    "pro-50",
    "ai-exhausted",
    "offline-taipei-12",
    "friends-f1",
    "friends-none",
    "clip-new",
    "clip-free-49",
    "clip-free-50",
    "clip-dup",
    "clip-free-47",
)

# Public Taipei venues (names + coords only). Fixed UUIDs, no live people.
TAIPEI_12 = (
    {"name": "Din Tai Fung Xinyi", "address": "台北市信義區市府路45號", "category": "food",
     "lat": 25.0363, "lng": 121.5645, "visited": 1, "photo": False},
    {"name": "Yongkang Beef Noodle", "address": "台北市大安區永康街17巷1號", "category": "food",
     "lat": 25.0324, "lng": 121.5296, "visited": 0, "photo": False},
    {"name": "Fika Fika Cafe", "address": "台北市中山區南京東路二段1號", "category": "cafe",
     "lat": 25.0522, "lng": 121.5220, "visited": 1, "photo": True},
    {"name": "Simple Kaffa", "address": "台北市大安區金華街199號", "category": "cafe",
     "lat": 25.0310, "lng": 121.5308, "visited": 0, "photo": False},
    {"name": "Ounce Taipei", "address": "台北市大安區安和路一段21巷7號", "category": "bar",
     "lat": 25.0386, "lng": 121.5517, "visited": 0, "photo": False},
    {"name": "Indulge Experimental Bistro", "address": "台北市中山區中山北路二段16巷23號", "category": "bar",
     "lat": 25.0534, "lng": 121.5228, "visited": 0, "photo": False},
    {"name": "Chiang Kai-shek Memorial Hall", "address": "台北市中正區中山南路21號", "category": "attraction",
     "lat": 25.0346, "lng": 121.5218, "visited": 3, "photo": True},
    {"name": "Taipei 101", "address": "台北市信義區信義路五段7號", "category": "attraction",
     "lat": 25.0339, "lng": 121.5645, "visited": 0, "photo": False},
    {"name": "W Taipei", "address": "台北市信義區忠孝東路五段10號", "category": "stay",
     "lat": 25.0408, "lng": 121.5652, "visited": 0, "photo": False},
    {"name": "Hotel Proverbs Taipei", "address": "台北市大安區大安路一段51巷7號", "category": "stay",
     "lat": 25.0426, "lng": 121.5462, "visited": 0, "photo": False},
    {"name": "Breeze Center", "address": "台北市松山區復興南路一段39號", "category": "shopping",
     "lat": 25.0462, "lng": 121.5440, "visited": 0, "photo": False},
    {"name": "Songshan Cultural and Creative Park", "address": "台北市信義區光復南路133號", "category": "shopping",
     "lat": 25.0437, "lng": 121.5606, "visited": 5, "photo": False},
)

UNSAVED_NEARBY = (
    {"name": "Elephant Mountain Trailhead", "address": "台北市信義區", "lat": 25.0270, "lng": 121.5764},
    {"name": "Four Four South Village", "address": "台北市信義區莊敬路51巷", "lat": 25.0322, "lng": 121.5603},
    {"name": "Taipei World Trade Center", "address": "台北市信義區信義路五段5號", "lat": 25.0335, "lng": 121.5616},
)

LINK_STUBS = {
    "instagram": "https://www.instagram.com/p/VerifySamePlace/",
    "googleMaps": "https://maps.app.goo.gl/VerifySamePlace",
    "placeName": "Din Tai Fung Xinyi",
    "liveNetwork": False,
}

EAT = frozenset({"food", "cafe", "bar"})
GO = frozenset({"attraction", "stay", "shopping"})
MULTI_CITIES = ("台北市", "台南市", "高雄市", "台中市", "新北市")
SCREENSHOT_SKIP = "SKIP：simulator not wired; live capture is ios.yml workflow_dispatch"
SCREENSHOT_NAME = "<flow>-<step>-<light|dark>-<lang>.png"

# Every HoP assertion, even when the flow is SKIP.
FLOW_ASSERTIONS = {
    "V1": (
        "saved-count-1",
        "capture-footer-saved-1",
        "dedup-two-sources",
        "analyze-single-write",
        "zh-hant-no-english",
    ),
    "V2": (
        "eat-6",
        "go-6",
        "minimaps-pins-match",
        "map-from-mini-inherits",
        "map-tab-own-state",
        "collected-4-12",
        "passport-root-from-collected",
        "home.saves",
        "saves.trips",
        "location-denied",
        "empty-state",
        "no-elephant-stickers",
    ),
    "V3": (
        "saved-pins",
        "unsaved-no-saved-pin",
        "coral-hex",
        "user-photo-pins",
        "no-google-photo-on-pin",
        "visited-ring",
        "unsaved-tap-no-beenHere",
        "no-saturation-overlay",
    ),
    "V4": (
        "map.card.beenHere",
        "visit-plus-one",
        "same-day-no-double",
        "passport-visit-plus-one",
        "sticker-color-stamp",
        "undo-and-relaunch",
        "visit-tiers-1-3-5",
        "passport-columns",
        "no-missions-streak-ledger",
        "no-location-prompt",
        "passport.root",
    ),
    "V5": (
        "save-50-ok",
        "save-51-unplaced-paywall",
        "paywall.benefit.unlimited",
        "paywall.no-ai-copy",
        "paywall.free-50-copy",
        "paywall.no-free-unlimited",
        "paywall.savedNote",
        "dismiss-and-relaunch-unplaced",
        "delete-then-promote",
        "pro-51-allowed",
        "ai.quotaExhausted",
        "settings-same-paywall",
        "paywall.retry",
        "saves.unplaced",
        "cold-start-no-paywall",
        "onboarding-no-paywall",
        "paywall.unavailable",
    ),
    "V6": (
        "cold-start-12",
        "no-locked-map-copy",
        "no-infinite-spinner",
        "offline-sync-15",
        "over-cap-unplaced",
    ),
    "V7": (
        "LS1",
        "M1",
        "M2",
        "S3",
        "G-a",
        "G-d",
        "S1'",
        "SK1",
        "SK2",
        "SK3",
        "LS3",
        "LS4",
        "S5",
        "S6",
        "S8",
        "SL1",
        "SL2",
        "SL3",
        "SL4",
        "SL5",
        "SL6",
        "PR4",
        "PR5",
        "W1",
        "W2",
        "W3",
        "Z1",
        "clip-cap50-copy",
    ),
    "V8": (
        "F-B1",
        "F-B2",
        "F-B3",
        "F-B4",
        "F-B6",
        "F-B7",
        "F-B9",
        "F-B10",
    ),
}


def pin_process_environment() -> None:
    os.environ["TZ"] = "UTC"
    os.environ["LANG"] = "C.UTF-8"
    os.environ["LC_ALL"] = "C.UTF-8"
    os.environ["LC_COLLATE"] = "C.UTF-8"
    os.environ["PYTHONHASHSEED"] = "0"
    os.environ["PYTHONUTF8"] = "1"


def repo_root() -> Path:
    here = Path(__file__).resolve()
    return here.parents[1] if here.name == "save_verify.py" else here.parent


def workspace_dir(root: Path) -> Path:
    override = os.environ.get("SAVE_VERIFY_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    return (root / ".verify").resolve()


def dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def emit(payload: dict[str, Any], code: int) -> int:
    sys.stdout.write(dumps(payload))
    return code


def relpath(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dumps(payload), encoding="utf-8")


def tree_text(root: Path) -> str:
    chunks: list[str] = []
    for base in SWIFT_ROOTS:
        folder = root / base
        if not folder.exists():
            continue
        for path in sorted(folder.rglob("*")):
            if path.suffix in {".swift", ".ts", ".tsx", ".js"} and path.is_file():
                chunks.append(path.read_text(encoding="utf-8"))
    return "\n".join(chunks)


def landed_prs(root: Path, cache: dict[str, str] | None = None) -> dict[int, bool]:
    text = cache.get("tree") if cache is not None else None
    if text is None:
        text = tree_text(root)
        if cache is not None:
            cache["tree"] = text
    landed: dict[int, bool] = {}
    for number, probes in PR_PROBES.items():
        landed[number] = all(probe in text for probe in probes) if probes else False
    return landed


def skip_reason(flow: str, landed: dict[int, bool]) -> str | None:
    if flow == "V6":
        return "SKIP：依賴離線冷啟動 PR 未開（U7）"
    missing = [number for number in FLOW_DEPS[flow] if not landed.get(number)]
    if not missing:
        return None
    joined = ",".join(f"#{n}" for n in missing)
    return f"SKIP：依賴 {joined} 未合併"


def place_row(index: int, spec: dict[str, Any], *, city: str | None = None) -> dict[str, Any]:
    address = spec.get("address") or f"{city or '台北市'} Public Landmark {index:02d}"
    visits = int(spec.get("visited") or 0)
    return {
        "address": address,
        "category": spec.get("category", "attraction"),
        "googlePhotoURL": (
            f"https://maps.googleapis.com/maps/api/place/photo"
            f"?maxwidth=400&photo_reference=verify-{index:02d}"
        ),
        "googlePlaceId": f"ChIJVERIFY{index:02d}TAIPEI000000",
        "hasUserPhoto": bool(spec.get("photo")),
        "id": f"20000000-0000-4000-8000-{index:012d}",
        "latitude": spec.get("lat", LOCATION["latitude"]),
        "longitude": spec.get("lng", LOCATION["longitude"]),
        "name": spec.get("name", f"Public Landmark {index:02d}"),
        "status": "visited" if visits else "wantToGo",
        "userPhotoURL": f"savvy://user-photo/{index:02d}" if spec.get("photo") else None,
        "visitCount": visits,
    }


def taipei_12_places() -> list[dict[str, Any]]:
    return [place_row(index + 1, spec) for index, spec in enumerate(TAIPEI_12)]


def many_places(count: int) -> list[dict[str, Any]]:
    places = taipei_12_places()
    next_index = len(places) + 1
    while len(places) < count:
        city = MULTI_CITIES[(next_index - 1) % len(MULTI_CITIES)]
        places.append(
            place_row(
                next_index,
                {
                    "name": f"Public Landmark {next_index:02d}",
                    "address": f"{city} Public Landmark {next_index:02d}",
                    "category": "attraction",
                    "lat": LOCATION["latitude"],
                    "lng": LOCATION["longitude"],
                    "visited": 0,
                    "photo": False,
                },
                city=city,
            )
        )
        next_index += 1
    return places[:count]


def friends_fixture(kind: str) -> dict[str, Any]:
    if kind != "f1":
        return {"accounts": [], "posts": []}
    return {
        "accounts": [
            {"handle": "verify.friend.one", "id": "friend-1", "name": "Verify Friend One"},
            {"handle": "verify.friend.two", "id": "friend-2", "name": "Verify Friend Two"},
        ],
        "posts": [
            {
                "authorId": "friend-1",
                "id": "40000000-0000-4000-8000-000000000001",
                "photoURL": "savvy://user-photo/friend-1",
                "placeName": "Fika Fika Cafe",
            },
            {
                "authorId": "friend-2",
                "id": "40000000-0000-4000-8000-000000000002",
                "photoURL": "savvy://user-photo/friend-2",
                "placeName": "Taipei 101",
            },
        ],
    }


def clip_payloads() -> dict[str, Any]:
    first = taipei_12_places()[0]
    listed = taipei_12_places()[:5]
    return {
        "googlePhotoRejected": {
            "photoURL": first["googlePhotoURL"],
            "placeName": first["name"],
        },
        "list": [{"alreadySaved": index == 0, "name": row["name"]} for index, row in enumerate(listed)],
        "single": {
            "name": first["name"],
            "photoURL": "savvy://user-photo/clip-share",
            "shortCode": "p/verifysame",
        },
    }


def build_seed(name: str) -> dict[str, Any]:
    if name not in SEEDS:
        raise KeyError(name)
    places: list[dict[str, Any]] = []
    tier = "free"
    offline = False
    ai_exhausted = False
    location_allowed = True
    friends = friends_fixture("none")
    account = "signed-in"
    if name == "empty-free":
        places = []
    elif name in {"taipei-12", "ai-exhausted", "offline-taipei-12", "friends-f1", "friends-none"}:
        places = taipei_12_places()
        ai_exhausted = name == "ai-exhausted"
        offline = name == "offline-taipei-12"
        friends = friends_fixture("f1" if name == "friends-f1" else "none")
    elif name == "free-49":
        places = many_places(49)
    elif name in {"free-50", "pro-50"}:
        places = many_places(50)
        tier = "pro" if name == "pro-50" else "free"
    elif name == "clip-new":
        account = "none"
    elif name == "clip-free-49":
        places = many_places(49)
    elif name == "clip-free-50":
        places = many_places(50)
    elif name == "clip-dup":
        places = [taipei_12_places()[0]]
    elif name == "clip-free-47":
        places = many_places(47)

    return {
        "account": account,
        "aiExhausted": ai_exhausted,
        "clock": CLOCK,
        "friends": friends,
        "language": LANGUAGE,
        "links": dict(LINK_STUBS),
        "locale": LOCALE,
        "location": dict(LOCATION),
        "locationAllowed": location_allowed,
        "name": name,
        "offline": offline,
        "places": places,
        "savedCount": len(places),
        "tier": tier,
        "tool": TOOL,
        "unplaced": [],
        "unsavedNearby": [dict(row) for row in UNSAVED_NEARBY] if name.startswith(("taipei", "offline", "friends", "ai-")) else [],
        "clip": clip_payloads() if name.startswith("clip-") else {},
    }


def decide_saved_place_insert(
    *,
    tier: str,
    saved_place_count: int,
    is_new_place: bool,
    limit: int = FREE_SAVED_PLACE_LIMIT,
) -> str:
    if not is_new_place or tier == "pro":
        return "allowed"
    return "allowed" if saved_place_count < limit else "over_free_limit"


def source_has(root: Path, needle: str, cache: dict[str, str]) -> bool:
    text = cache.get("tree")
    if text is None:
        text = tree_text(root)
        cache["tree"] = text
    return needle in text


def assertion(item_id: str, ok: bool, detail: str) -> dict[str, Any]:
    return {
        "detail": detail,
        "id": item_id,
        "ok": ok,
        "status": "PASS" if ok else "FAIL",
    }


def skipped_row(item_id: str, reason: str) -> dict[str, Any]:
    return {
        "detail": reason,
        "id": item_id,
        "ok": False,
        "status": "SKIP",
    }


def skipped_assertions(flow: str, reason: str) -> list[dict[str, Any]]:
    return [skipped_row(f"{flow}.{item_id}", reason) for item_id in FLOW_ASSERTIONS[flow]]


def merge_assertions(
    flow: str,
    reason: str,
    computed: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    by_id = {row["id"]: row for row in computed}
    rows = []
    catalog = {f"{flow}.{item_id}" for item_id in FLOW_ASSERTIONS[flow]}
    for item_id in FLOW_ASSERTIONS[flow]:
        full = f"{flow}.{item_id}"
        rows.append(by_id.get(full) or skipped_row(full, reason))
    for row in computed:
        if row["id"] not in catalog:
            rows.append(row)
    return rows


def evaluate_v5(root: Path, cache: dict[str, str]) -> list[dict[str, Any]]:
    rows = [
        skipped_row(
            f"V5.{item}",
            "SKIP：production SavePlaceLimitGate and save flow are not executed here",
        )
        for item in ("save-50-ok", "save-51-unplaced-paywall", "pro-51-allowed")
    ]
    rows.append(
        assertion(
            "V5.reference-fixture.save-50-ok",
            decide_saved_place_insert(tier="free", saved_place_count=49, is_new_place=True)
            == "allowed",
            "Python reference fixture only: free 49 → 50th insert allowed",
        )
    )
    rows.append(
        assertion(
            "V5.reference-fixture.save-51-unplaced-paywall",
            decide_saved_place_insert(tier="free", saved_place_count=50, is_new_place=True)
            == "over_free_limit",
            "Python reference fixture only: free 50 → over_free_limit",
        )
    )
    rows.append(
        assertion(
            "V5.reference-fixture.pro-51-allowed",
            decide_saved_place_insert(tier="pro", saved_place_count=50, is_new_place=True)
            == "allowed",
            "Python reference fixture only: pro 50 → 51st allowed",
        )
    )
    rows.append(
        assertion(
            "V5.paywall.savedNote",
            source_has(root, FINAL_IDS["paywall.savedNote"], cache)
            and source_has(root, SAVED_50_COPY, cache),
            f"{FINAL_IDS['paywall.savedNote']} holds {SAVED_50_COPY}",
        )
    )
    rows.append(
        assertion(
            "V5.paywall.retry",
            source_has(root, FINAL_IDS["paywall.retry"], cache),
            "retry = paywall.retry",
        )
    )
    rows.append(
        assertion(
            "V5.saves.unplaced",
            source_has(root, FINAL_IDS["saves.unplaced"], cache)
            and source_has(root, FINAL_IDS["saves.unplaced.row"], cache),
            "saves.unplaced + saves.unplaced.row.<placeId>",
        )
    )
    rows.append(
        assertion(
            "V5.ai.quotaExhausted",
            source_has(root, FINAL_IDS["ai.quotaExhausted"], cache),
            "ai.quotaExhausted with no paywall.root",
        )
    )
    return rows


def evaluate_v7(root: Path, cache: dict[str, str]) -> list[dict[str, Any]]:
    guard_test = root / "Tests/SocialPlacePipelineTests/ShareRouteCodecTests.swift"
    guard_source = guard_test.read_text(encoding="utf-8") if guard_test.is_file() else ""
    rows = [
        skipped_row(
            "V7.clip-cap50-copy",
            f"SKIP：actual App Clip cap screen must assert {SAVED_50_COPY}; screen not executed here",
        ),
        assertion(
            "V7.clip-ids",
            all(
                source_has(root, token, cache)
                for token in ("clip.pending", "app.handoff.confirmList", "clip.skoverlay")
            ),
            "clip.pending / app.handoff.confirmList / clip.skoverlay (pending-only flow)",
        ),
        assertion(
            "V7.no-google-payload",
            "testSharedPublicPayloadsContainNoGoogleDomainURLs" in guard_source,
            "ShareRouteCodecTests Google-domain guard source exists (not executed here)",
        ),
    ]
    return rows


def evaluate_flow(flow: str, root: Path, cache: dict[str, str]) -> list[dict[str, Any]]:
    ui_skip = "SKIP：UI 步驟需 macOS workflow_dispatch（無新增自動 macOS job）"
    computed: list[dict[str, Any]] = []
    if flow == "V5":
        computed = evaluate_v5(root, cache)
    elif flow == "V7":
        computed = evaluate_v7(root, cache)
    return merge_assertions(flow, ui_skip, computed)


def cmd_seed(root: Path, workspace: Path, name: str) -> tuple[int, dict[str, Any]]:
    if name not in SEEDS:
        return 2, {
            "error": "unknown seed",
            "ok": False,
            "seed": name,
            "seeds": list(SEEDS),
            "tool": TOOL,
            "usage": USAGE,
        }
    payload = build_seed(name)
    dest = workspace / "seeds" / f"{name}.json"
    write_json(dest, payload)
    write_json(workspace / "last.json", {"command": "seed", "ok": True, "seed": payload, "tool": TOOL})
    return 0, {
        "command": "seed",
        "ok": True,
        "path": relpath(root, dest),
        "placeCount": payload["savedCount"],
        "seed": payload,
        "tool": TOOL,
        "workspace": relpath(root, workspace),
    }


def load_seed(workspace: Path, name: str) -> dict[str, Any]:
    path = workspace / "seeds" / f"{name}.json"
    if not path.is_file():
        raise FileNotFoundError(f"seed is missing; run ./verify seed {name}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    expected = build_seed(name)
    if payload != expected:
        raise ValueError(f"seed drift: {name} does not match the fixed fixture")
    return payload


def cmd_run(root: Path, workspace: Path, flow: str) -> tuple[int, dict[str, Any]]:
    if flow not in FLOW_DEPS:
        return 2, {
            "error": "unknown flow",
            "flow": flow,
            "flows": list(FLOW_DEPS),
            "ok": False,
            "tool": TOOL,
            "usage": USAGE,
        }
    cache: dict[str, str] = {}
    landed = landed_prs(root, cache)
    reason = skip_reason(flow, landed)
    seeds_used = []
    for seed_name in FLOW_SEEDS[flow]:
        try:
            load_seed(workspace, seed_name)
        except FileNotFoundError:
            cmd_seed(root, workspace, seed_name)
            load_seed(workspace, seed_name)
        except (ValueError, json.JSONDecodeError) as error:
            return 1, {"error": str(error), "flow": flow, "ok": False, "tool": TOOL}
        seeds_used.append(seed_name)

    if reason:
        result = {
            "assertions": skipped_assertions(flow, reason),
            "command": "run",
            "depends": [f"#{n}" for n in FLOW_DEPS[flow]],
            "flow": flow,
            "ok": False,
            "passed": False,
            "reason": reason,
            "seeds": seeds_used,
            "status": "SKIP",
            "tool": TOOL,
        }
        write_json(workspace / "results" / f"{flow}.json", result)
        write_json(workspace / "last.json", result)
        return 0, result

    if flow in {"V5", "V7"}:
        assertions = evaluate_flow(flow, root, cache)
        failed = any(row["status"] == "FAIL" for row in assertions)
        if failed:
            status = "FAIL"
            reason = None
        elif any(row["status"] == "SKIP" for row in assertions):
            status = "SKIP"
            reason = "SKIP：UI 步驟需 macOS workflow_dispatch（無新增自動 macOS job）"
        else:
            status = "PASS"
            reason = None
    else:
        reason = "SKIP：UI 步驟需 macOS workflow_dispatch（無新增自動 macOS job）"
        assertions = skipped_assertions(flow, reason)
        failed = False
        status = "SKIP"
    result = {
        "assertions": assertions,
        "command": "run",
        "depends": [f"#{n}" for n in FLOW_DEPS[flow]],
        "flow": flow,
        "ok": status == "PASS",
        "passed": status == "PASS",
        "reason": reason,
        "seeds": seeds_used,
        "status": status,
        "tool": TOOL,
    }
    write_json(workspace / "results" / f"{flow}.json", result)
    write_json(workspace / "last.json", result)
    return (1 if failed else 0), result


def screenshot_filename(page: str) -> str:
    theme = os.environ.get("SAVE_VERIFY_THEME", "light")
    lang = os.environ.get("SAVE_VERIFY_LANG", "en")
    if theme not in {"light", "dark"}:
        theme = "light"
    stem = page[:-4] if page.endswith(".png") else page
    if re.fullmatch(r".+-.+-(light|dark)-[A-Za-z0-9-]+", stem):
        return f"{stem}.png"
    if re.fullmatch(r"V[1-8]-\d+-.+", stem):
        return f"{stem}-{theme}-{lang}.png"
    return f"{stem}-1-{theme}-{lang}.png"


def cmd_screenshot(root: Path, workspace: Path, page: str) -> tuple[int, dict[str, Any]]:
    dest_dir = workspace / "screenshots"
    dest_dir.mkdir(parents=True, exist_ok=True)
    filename = screenshot_filename(page)
    dest = dest_dir / filename
    result = {
        "command": "screenshot",
        "naming": SCREENSHOT_NAME,
        "ok": False,
        "page": page,
        "path": relpath(root, dest),
        "planned": filename,
        "reason": SCREENSHOT_SKIP,
        "sha256": None,
        "source": None,
        "status": "SKIP",
        "tool": TOOL,
    }
    write_json(dest.with_suffix(".json"), result)
    write_json(workspace / "screenshots" / f"{page}.json", result)
    write_json(workspace / "last.json", result)
    return 0, result


def cmd_check(root: Path, workspace: Path) -> tuple[int, dict[str, Any]]:
    for name in SEEDS:
        code, payload = cmd_seed(root, workspace, name)
        if code != 0:
            return code, payload

    flows: dict[str, Any] = {}
    failed = False
    for flow in FLOW_DEPS:
        code, payload = cmd_run(root, workspace, flow)
        flows[flow] = payload
        if payload.get("status") == "FAIL":
            failed = True
        if code == 2:
            return code, payload

    screenshots: dict[str, Any] = {}
    shot_dir = workspace / "screenshots"
    if shot_dir.is_dir():
        for png in sorted(shot_dir.glob("*.png")):
            screenshots[png.name] = {
                "path": relpath(root, png),
                "sha256": sha256_file(png),
            }

    first = dumps(flows)
    second = dumps({name: cmd_run(root, workspace, name)[1] for name in FLOW_DEPS})
    deterministic = first == second
    result = {
        "clock": CLOCK,
        "command": "check",
        "deterministic": deterministic,
        "flows": {
            name: {
                "reason": body.get("reason"),
                "status": body.get("status"),
                "assertions": body.get("assertions"),
            }
            for name, body in flows.items()
        },
        "language": LANGUAGE,
        "locale": LOCALE,
        "location": dict(LOCATION),
        "ok": (not failed) and deterministic,
        "passed": False,
        "screenshots": screenshots,
        "statuses": {name: body.get("status") for name, body in flows.items()},
        "tool": TOOL,
        "workspace": relpath(root, workspace),
    }
    # check.ok means no FAIL. It is not a product PASS while flows are SKIP.
    if any(body.get("status") == "PASS" for body in flows.values()) and not failed:
        result["passed"] = True
    write_json(workspace / "report.json", result)
    write_json(workspace / "last.json", result)
    return (1 if failed or not deterministic else 0), result


def dispatch(argv: list[str], *, root: Path | None = None) -> tuple[int, dict[str, Any]]:
    pin_process_environment()
    root = repo_root() if root is None else root
    workspace = workspace_dir(root)
    parser = argparse.ArgumentParser(prog="./verify", add_help=True)
    parser.add_argument("command", nargs="?", choices=("seed", "run", "screenshot", "check"))
    parser.add_argument("target", nargs="?")
    try:
        args = parser.parse_args(argv)
    except SystemExit as error:
        code = int(error.code) if error.code is not None else 2
        return code, {"error": "usage", "ok": False, "tool": TOOL, "usage": USAGE}

    if args.command is None:
        return 2, {"error": "usage", "ok": False, "tool": TOOL, "usage": USAGE}
    if args.command == "seed":
        if not args.target:
            return 2, {
                "error": "usage",
                "ok": False,
                "seeds": list(SEEDS),
                "tool": TOOL,
                "usage": USAGE,
            }
        return cmd_seed(root, workspace, args.target)
    if args.command == "run":
        if not args.target:
            return 2, {
                "error": "usage",
                "flows": list(FLOW_DEPS),
                "ok": False,
                "tool": TOOL,
                "usage": USAGE,
            }
        return cmd_run(root, workspace, args.target)
    if args.command == "screenshot":
        if not args.target:
            return 2, {
                "error": "usage",
                "naming": SCREENSHOT_NAME,
                "ok": False,
                "tool": TOOL,
                "usage": USAGE,
            }
        return cmd_screenshot(root, workspace, args.target)
    if args.target:
        return 2, {"error": "usage", "ok": False, "tool": TOOL, "usage": USAGE}
    return cmd_check(root, workspace)


def main(argv: list[str] | None = None) -> int:
    code, payload = dispatch(sys.argv[1:] if argv is None else argv)
    return emit(payload, code)


if __name__ == "__main__":
    raise SystemExit(main())
