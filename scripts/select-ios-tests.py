#!/usr/bin/env python3
"""Select PR UI coverage from the exact checkout diff; unknown inputs run full."""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

RAIL = "SAVEUITests/SAVEScreenshotRailTests/"
ONBOARDING = "SAVEUITests/SAVEOnboardingCarouselTests"
TRIP_SHEET = RAIL + "testTripStopEditorSurfaceIsReachable"
BASELINE = [RAIL + name for name in (
    "testCaptureAtlasProductionParity",
    "testCaptureFiveTabLanding",
    "testDoodlePaywallParity",
    "testHomeAndPassportWarmDarkMode",
    "testAtlasHomeAndSavesRenderPersistedPlaceData",
    "testHomeSearchAndPendingCandidateOpenDirectly",
    "testCaptureMultipleResultsExcludeOlderClues",
    "testEmptyHomeStartsCaptureAndKeepsSourceOnlyUnconfirmed",
    "testSavedPlaceEntryUsesSingleCanonicalDetail",
    "testUnsavedAndSocialDetailsUsePostcardDetailFamily",
    "testAnalyzedMapLinkPersistsAsTripStopAfterRelaunch",
    "testTripMapMarkerDetailReturnsToScopedTabs",
    "testCaptureAtlasTripsAndLiveMaps",
    "testMapSearchDrawerResizesThroughThreeStages",
    "testTripUsesPlanMapAndTopSharePostcardPocket",
    "testRapidChromeTransitionsKeepAppAlive",
    "testPassportAndPostalImportSurfacesAreReachable",
    "testSocialPassportGridAndComposer",
    "testPassportListsEntryOpensListsDirectly",
    "testFriendsComingSoon",
)] + [ONBOARDING, RAIL + "testPassportTutorialReplaysWithoutAddingPlaces"]

# Exact-file allowlist: adding another view/service requires coverage review.
SURFACES = {
    "SAV-E/Views/Map/SaveMapDrawerPanel.swift": "map",
    "SAV-E/Views/Onboarding/OnboardingView.swift": "onboarding",
    "SAV-E/Views/Plan/SavePlanView.swift": "plan",
}
TESTS = {
    "map": [RAIL + name for name in (
        "testMapSearchDrawerResizesThroughThreeStages",
        "testSavedPlaceEntryUsesSingleCanonicalDetail",
        "testTripMapMarkerDetailReturnsToScopedTabs",
        "testRapidChromeTransitionsKeepAppAlive",
    )],
    "onboarding": [ONBOARDING, RAIL + "testPassportTutorialReplaysWithoutAddingPlaces"],
    "plan": [RAIL + name for name in (
        "testPlanChatDraftAndConversationSurviveTabChange",
        "testPlanTabDraftsFromSavedMapStamps",
        "testPlanCandidateCanBeConfirmedSavedAndOpened",
        "testTripUsesPlanMapAndTopSharePostcardPocket",
        "testAnalyzedMapLinkPersistsAsTripStopAfterRelaunch",
    )],
}
# Full/main retains every frozen selector plus the social passport flow. Plan extras belong on the
# Plan route only. Folding them into FULL made this CI-scoping PR require
# testPlanTabDraftsFromSavedMapStamps, which is not on current main and
# failed 3/3 on run 34019378064 after compose never produced plan.draft.
FULL = list(BASELINE) + [
    RAIL + "testHomeListProgressiveSearch",
    RAIL + "testMiniMapOpensMapWithCarriedFilterAndCityChange",
]

# Temporary #279 iteration profiles. Empty SAVE_UI_TEST_FOCUS keeps default
# selection. Never applied on main. Delete FOCUS_PROFILES + requested_focus()
# to revert. Tests are a subset of FULL; nothing is skipped or rewritten.
FOCUS_PROFILES = {
    "tile-town-home": {
        "tests": [RAIL + name for name in (
            "testCaptureAtlasProductionParity",
            "testCaptureFiveTabLanding",
            "testAtlasHomeAndSavesRenderPersistedPlaceData",
            "testCaptureMultipleResultsExcludeOlderClues",
            "testCaptureAtlasTripsAndLiveMaps",
            "testFriendsComingSoon",
            "testHomeListProgressiveSearch",
        )],
        "trip": False,
        "units": False,
    },
}


def requested_focus():
    """Return a named focus profile, or empty for default/full coverage.

    Main pushes never focus, even if the env is set, so the merge gate stays
    the full suite. Unknown names fail loudly instead of silently widening.
    """
    if os.environ.get("GITHUB_REF") == "refs/heads/main":
        return ""
    return os.environ.get("SAVE_UI_TEST_FOCUS", "").strip()


def select(paths, *, full=False):
    if full or not paths:
        return result("full", FULL, trip=True)
    surfaces = set()
    unit = False
    for path in paths:
        if path.endswith(".md") or path.startswith((
            "specs/", "docs/", "design-prompts/", "backend/", "save-rn/",
            "services/", "supabase/", "Prototypes/AtlasPostcard/decisions/",
        )):
            continue  # Same non-iOS exclusions as the previous workflow.
        if path in SURFACES:
            surfaces.add(SURFACES[path])
        elif path.startswith("Tests/SocialPlacePipelineTests/") and path.endswith(".swift"):
            unit = True
        else:
            return result("full", FULL, trip=True)
    if surfaces:
        tests = BASELINE[:2]  # Keep production parity and five-tab smoke on every UI PR.
        for surface in sorted(surfaces):
            tests += TESTS[surface]
        return result("+".join(sorted(surfaces)), list(dict.fromkeys(tests)),
                      trip="plan" in surfaces)
    return result("unit" if unit else "non-ios", [], run=unit)


def result(profile, tests, *, trip=False, run=True, units=None):
    if units is None:
        units = run
    return {"profile": profile, "run": run, "ui": bool(tests),
            "trip": trip, "units": units, "tests": tests}


def changed_paths(base):
    if not re.fullmatch(r"[0-9a-f]{40}", base):
        raise ValueError("missing or invalid base SHA")
    # checkout's PR merge commit has its base parent with fetch-depth: 2.
    # --no-renames checks both sides of a move; NUL delimiters preserve filenames.
    raw = subprocess.check_output([
        "git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--",
    ])
    return [p.decode("utf-8") for p in raw.split(b"\0") if p]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    paths = []
    reason = "non-PR runs always use full integration coverage"
    focus = requested_focus()
    if focus:
        if focus not in FOCUS_PROFILES:
            known = ", ".join(sorted(FOCUS_PROFILES))
            raise SystemExit(
                f"unknown SAVE_UI_TEST_FOCUS={focus!r}; known profiles: {known}"
            )
        spec = FOCUS_PROFILES[focus]
        plan = result(
            f"focus:{focus}",
            spec["tests"],
            trip=spec["trip"],
            run=True,
            units=spec.get("units", False),
        )
        reason = (
            f"SAVE_UI_TEST_FOCUS={focus}; iteration set only "
            "(unset the env to restore default/full coverage)"
        )
        if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
            try:
                paths = changed_paths(os.environ.get("PR_BASE_SHA", ""))
            except (ValueError, UnicodeError, subprocess.CalledProcessError):
                paths = []
    elif os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
        try:
            paths = changed_paths(os.environ.get("PR_BASE_SHA", ""))
            plan = select(paths)
            reason = "exact base-to-checkout diff; unknown paths select full"
        except (ValueError, UnicodeError, subprocess.CalledProcessError) as error:
            plan = select([], full=True)
            reason = f"diff unavailable; full coverage: {type(error).__name__}"
    else:
        plan = select([], full=True)
    plan.update(reason=reason, changed_paths=paths)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "ios-test-selection.json").write_text(json.dumps(plan, indent=2) + "\n")
    (args.output_dir / "ios-ui-args.txt").write_text(
        "".join(f"-only-testing:{test}\n" for test in plan["tests"]))
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for key in ("profile", "run", "ui", "trip", "units"):
            value = str(plan[key]).lower() if isinstance(plan[key], bool) else plan[key]
            output.write(f"{key}={value}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"### iOS coverage: {plan['profile']}\n\n{reason}.\n\n")
        summary.write(
            f"Build: {plan['run']}; units: {plan['units']}; "
            f"UI selectors: {len(plan['tests'])}; "
            f"isolated Trip sheet: {plan['trip']}.\n\n"
        )
        for test in plan["tests"] + ([TRIP_SHEET] if plan["trip"] else []):
            summary.write(f"- `{test}`\n")
    print(json.dumps(plan, indent=2))


if __name__ == "__main__":
    main()
