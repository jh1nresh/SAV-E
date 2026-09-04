#!/usr/bin/env python3
"""Linux-safe source + catalog check for Passport Today on Savvy v0."""

from __future__ import annotations

import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def missions(
    waiting_clues: int,
    has_private_stamp: bool,
    has_non_guide_stamp: bool,
    friends_empty: bool,
    has_shared_invite: bool,
) -> list[str]:
    result: list[str] = []
    if waiting_clues >= 1:
        result.append("confirm_waiting_clue")
    if has_private_stamp or has_non_guide_stamp:
        result.append("share_recommendation")
    if friends_empty or not has_shared_invite:
        result.append("invite_or_follow_friend")
    return result[:3]


def check_catalog_decision_table() -> None:
    expect(
        missions(0, False, False, False, True) == [],
        "strip must hide when no live mission applies",
    )
    expect(
        missions(1, True, True, True, False)
        == [
            "confirm_waiting_clue",
            "share_recommendation",
            "invite_or_follow_friend",
        ],
        "order is confirm → share → invite",
    )
    expect(
        missions(0, False, False, True, True) == ["invite_or_follow_friend"],
        "empty friends still shows invite",
    )
    expect(
        missions(0, False, False, False, False) == ["invite_or_follow_friend"],
        "never shared invite still shows invite",
    )
    expect(
        missions(0, False, True, False, True) == ["share_recommendation"],
        "a non-publicGuide stamp shows share",
    )
    expect(
        missions(2, False, False, False, True) == ["confirm_waiting_clue"],
        "waiting clues show confirm only when share/invite do not apply",
    )
    expect(len(missions(1, True, True, True, False)) <= 3, "cap is 3")


def check_sources(root: Path) -> None:
    profile = (root / "SAV-E/Views/Profile/ProfileView.swift").read_text()
    catalog = (root / "SAV-E/Models/UserProfile.swift").read_text()
    content = (root / "SAV-E/App/ContentView.swift").read_text()
    spec = (root / "specs/2026-09-04-save-passport-today-on-savvy-v0.md").read_text()

    expect("if !todayMissions.isEmpty" in profile, "empty catalog must hide the strip")
    expect("TODAY ON SAVVY" in profile, "English eyebrow")
    expect("今日 Savvy" in profile, "Chinese eyebrow")
    expect("Up to three real next steps" in profile, "English subtitle")
    expect("最多三件真正要做的事" in profile, "Chinese subtitle")
    expect("profile.today.confirmWaitingClue" in profile, "confirm a11y id")
    expect("profile.today.shareRecommendation" in profile, "share a11y id")
    expect("profile.today.inviteFriend" in profile, "invite a11y id")
    expect("onReviewAll()" in profile, "confirm uses Home review destination")
    expect("onReviewAll:" in content, "ContentView wires onReviewAll")
    expect(".saves" in content, "review destination is Saves")
    expect("confirm_waiting_clue" in catalog, "catalog id confirm")
    expect("share_recommendation" in catalog, "catalog id share")
    expect("invite_or_follow_friend" in catalog, "catalog id invite")
    expect("SavePassportInviteShareStore" in catalog, "invite flag is local, not a grant")
    expect("profile.today.confirmWaitingClue" in spec, "spec keeps a11y ids")

    stamp = profile.find("profile.stampLedger")
    strip = profile.find("PassportTodayOnSavvyStrip")
    pocket = profile.find("profile.controlPocket")
    expect(stamp != -1 and strip != -1 and pocket != -1, "placement markers exist")
    expect(stamp < strip, "strip follows stamp ledger")
    expect(strip < pocket, "strip precedes control pocket")

    forbidden = (
        "SaveStoreKitService",
        "SaveEntitlementStore",
        "serverVerifiedTier",
        "locallyObservedTier",
        '"XP"',
        "quest board",
        "streak calendar",
    )
    for token in forbidden:
        expect(token not in profile, f"ProfileView must not contain {token}")
        expect(token not in catalog, f"UserProfile must not contain {token}")


def main() -> None:
    root = Path.cwd()
    check_catalog_decision_table()
    check_sources(root)
    print("Validated Passport Today on Savvy v0.")


if __name__ == "__main__":
    main()
