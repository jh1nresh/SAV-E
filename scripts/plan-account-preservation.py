#!/usr/bin/env python3
"""Prepare a private, read-only reconciliation proposal; never authorize a cutover."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

spec = importlib.util.spec_from_file_location("account_audit", Path(__file__).with_name("compare-account-exports.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

# These are original-source fields, not a promotion to captured-text evidence.
# An empty target can also be an intentional deletion, so even these proposals
# require review and an exact live precondition before any future write.
SOURCE_CONTENT = {"source_url", "raw_text"}


def digest(value):
    return hashlib.sha256(audit.canonical(value).encode()).hexdigest()


def partial_source(root):
    """Inspect verified returned records without treating unavailable data as empty."""
    root = Path(root)
    raw_manifest, manifest = audit.read_json(root / "manifest.json")
    if not isinstance(manifest, dict):
        raise audit.InvalidExport("Invalid manifest shape")
    if manifest.get("allRequestsSucceeded") is True:
        return (*audit.load_snapshot(root, audit.LEGACY), hashlib.sha256(raw_manifest).hexdigest())
    failed = manifest.get("failedResources")
    if (manifest.get("source") != audit.LEGACY or manifest.get("safeToCutOver") is not False
            or manifest.get("allRequestsSucceeded") is not False
            or not manifest.get("finishedAt")
            or not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("accountSubjectSHA256", "")))
            or failed != ["lists"]):
        raise audit.InvalidExport("Unsupported incomplete snapshot; preservation cannot be planned")
    # The only known partial case is a missing legacy lists API. Keep it a
    # blocking coverage gap. Never synthesize lists=[] or a successful manifest.
    expected = {name: path for name, path in audit.CORE.items() if name != "lists"}
    resources = {}
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise audit.InvalidExport("Missing manifest entries")
    for entry in entries:
        if not isinstance(entry, dict):
            raise audit.InvalidExport("Invalid manifest entry")
        name = next((name for name in expected if entry.get("file") == name + ".json"), None)
        if name is None or name in resources or entry.get("path") != expected[name]:
            raise audit.InvalidExport("Unexpected or duplicate export resource")
        raw, payload = audit.read_json(root / (name + ".json"))
        if len(raw) != entry.get("bytes") or hashlib.sha256(raw).hexdigest() != entry.get("sha256"):
            raise audit.InvalidExport("Snapshot checksum mismatch")
        if name == "profile":
            valid = isinstance(payload, dict) and isinstance(payload.get("id"), str) and bool(payload["id"])
        else:
            valid = isinstance(payload, list) and all(isinstance(row, dict) for row in payload)
        if not valid:
            raise audit.InvalidExport("Invalid export shape")
        resources[name] = payload
    if set(resources) != set(expected):
        raise audit.InvalidExport("Snapshot omits an undeclared resource")
    return manifest, resources, hashlib.sha256(raw_manifest).hexdigest()


def plan(source, target):
    old_manifest, old, source_digest = partial_source(source)
    new_manifest, new = audit.load_snapshot(target, audit.MANAGED)
    target_raw, _ = audit.read_json(Path(target) / "manifest.json")
    if (old_manifest["accountSubjectSHA256"] != new_manifest["accountSubjectSHA256"]
            or old["profile"]["id"] != new["profile"]["id"]):
        raise audit.InvalidExport("Account identities differ")
    owner = old["profile"]["id"]
    resources = {}
    owned_resources = {"places", "trips", "memory-captures", "memory-preferences", "recommendation-outcomes"}
    for name in sorted(old.keys() | new.keys()):
        before = audit.indexed(old[name], name) if name in old else {}
        after = audit.indexed(new[name], name) if name in new else {}
        for row in [*before.values(), *after.values()]:
            if name in owned_resources and "user_id" in row and row["user_id"] != owner:
                raise audit.InvalidExport("Resource ownership differs")
        missing, content, conflicts = [], [], []
        for key in sorted(before.keys() - after.keys()):
            # Retain the exact exported row, including unresolved references.
            # It is a review proposal, not a filtered payload ready for POST.
            missing.append({"id": key, "source": before[key], "requiresReview": True})
        for key in sorted(before.keys() & after.keys()):
            left, right = before[key], after[key]
            fields = {}
            for field in sorted(left.keys() | right.keys()):
                if (field in left) == (field in right) and left.get(field) == right.get(field):
                    continue
                value = {"sourcePresent": field in left, "targetPresent": field in right,
                         "source": left.get(field), "target": right.get(field)}
                if (name == "memory-captures" and field in SOURCE_CONTENT
                        and isinstance(left.get(field), str) and left[field].strip()
                        and field in right and right[field] in (None, "")):
                    content.append({"id": key, "field": field, **value,
                                    "expectedTargetRowSHA256": digest(right), "requiresReview": True})
                else:
                    fields[field] = value
            if fields:
                conflicts.append({"id": key, "fields": fields,
                                  "expectedTargetRowSHA256": digest(right)})
        resources[name] = {"sourceCount": len(before) if name in old else None,
                           "sourceUnavailable": name not in old, "targetCount": len(after),
                           "missingRecords": missing, "sourceContentProposals": content,
                           "conflicts": conflicts, "keepTargetOnly": sorted(after.keys() - before.keys())}
    return {
        "version": 1, "mode": "review_only", "safeToApply": False, "safeToCutOver": False,
        "sourceManifestSHA256": source_digest,
        "targetManifestSHA256": hashlib.sha256(target_raw).hexdigest(),
        "accountSubjectSHA256": old_manifest["accountSubjectSHA256"],
        "sourceFailedResources": old_manifest["failedResources"],
        "blockingCoverage": [*old_manifest["failedResources"], "exact social permissions and relationships",
                             "device-only data and media", "other accounts", "live changes since snapshots"],
        "resources": resources,
        "policy": "No writes, deletes, consent reconstruction, workflow settlement or source-evidence promotion. Review proposals and live preconditions before preparing an executable migration.",
    }


def write_plan(path, report):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        write_plan(args.output, plan(args.source, args.target))
    except (audit.InvalidExport, OSError, ValueError, TypeError, KeyError):
        print("Preservation proposal failed; no data changed or cutover authorized.", file=sys.stderr)
        return 1
    print("Private review proposal saved. Coverage gaps remain blocking; no data changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
