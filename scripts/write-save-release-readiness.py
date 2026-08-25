#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path


PROJECT_FILE = Path("SAV-E.xcodeproj/project.pbxproj")


def unique_setting(project: str, name: str) -> str:
    values = {
        value.strip().strip('"')
        for value in re.findall(rf"\b{re.escape(name)} = ([^;]+);", project)
    }
    if len(values) != 1:
        raise SystemExit(f"expected one {name}, found {sorted(values)}")
    return values.pop()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write the Savvy main-branch release-readiness receipt."
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True, type=int)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise SystemExit("commit must be a full 40-character lowercase SHA")
    if args.run_attempt < 1:
        raise SystemExit("run-attempt must be a positive integer")

    project = PROJECT_FILE.read_text(encoding="utf-8")
    version = unique_setting(project, "MARKETING_VERSION")
    build = unique_setting(project, "CURRENT_PROJECT_VERSION")
    bundle_identifier = "com.wanderly.app"
    if f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_identifier};" not in project:
        raise SystemExit("canonical Savvy app bundle identifier is missing")

    receipt = {
        "contractVersion": "save-release-readiness/v1",
        "product": "Savvy",
        "source": {
            "repository": args.repository,
            "commit": args.commit,
            "workflowRunId": args.run_id,
            "workflowRunAttempt": args.run_attempt,
        },
        "candidate": {
            "project": "SAV-E.xcodeproj",
            "scheme": "SAV-E",
            "configuration": "Release",
            "destination": "generic/platform=iOS",
            "bundleIdentifier": bundle_identifier,
            "marketingVersion": version,
            "buildNumber": build,
            "signed": False,
            "credentials": "synthetic-ci-only",
        },
        "verification": {
            "debugGenericSimulatorBuild": "passed",
            "focusedUnitTests": "passed",
            "releaseGenericDeviceBuild": "passed",
            "backendCI": "passed",
            "saveRnContractCI": "passed",
            "evidenceRubricCI": "passed",
        },
        "distribution": {
            "status": "awaiting-human-approval",
            "required": [
                "signed archive",
                "App Store Connect upload",
                "TestFlight device smoke",
            ],
        },
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
