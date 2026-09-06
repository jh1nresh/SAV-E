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
    "testAtlasHomeAndSavesRenderPersistedPlaceData",
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
FULL = list(dict.fromkeys(BASELINE + sum(TESTS.values(), [])))


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


def result(profile, tests, *, trip=False, run=True):
    return {"profile": profile, "run": run, "ui": bool(tests),
            "trip": trip, "tests": tests}


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
    if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
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
        for key in ("profile", "run", "ui", "trip"):
            value = str(plan[key]).lower() if isinstance(plan[key], bool) else plan[key]
            output.write(f"{key}={value}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"### iOS coverage: {plan['profile']}\n\n{reason}.\n\n")
        summary.write(f"Build + unit: {plan['run']}; UI selectors: {len(plan['tests'])}; "
                      f"isolated Trip sheet: {plan['trip']}.\n\n")
        for test in plan["tests"] + ([TRIP_SHEET] if plan["trip"] else []):
            summary.write(f"- `{test}`\n")
    print(json.dumps(plan, indent=2))


if __name__ == "__main__":
    main()
