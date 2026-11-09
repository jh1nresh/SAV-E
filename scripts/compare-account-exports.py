#!/usr/bin/env python3
"""Offline account preservation audit. Never writes account data or authorizes cutover."""
import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

LEGACY = "https://wanderly-api-production.up.railway.app"
MANAGED = "https://save-backend-production.up.railway.app"
CORE = {
    "profile": "/profile", "places": "/places", "trips": "/trips",
    "memory-candidates": "/memory/candidates", "memory-captures": "/memory/captures",
    "memory-preferences": "/v0/memory-preferences",
    "recommendation-outcomes": "/v0/recommendation-outcomes", "lists": "/v0/lists",
}
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", re.I)


class InvalidExport(ValueError):
    pass


def read_json(path):
    if path.is_symlink() or not path.is_file():
        raise InvalidExport("Export file is absent or is a symbolic link")
    try:
        data = path.read_bytes()
        return data, json.loads(data)
    except (OSError, ValueError):
        raise InvalidExport("Export file is unreadable or malformed") from None


def load_snapshot(root, expected_origin):
    root = Path(root)
    _, manifest = read_json(root / "manifest.json")
    if (not isinstance(manifest, dict) or manifest.get("source") != expected_origin
            or manifest.get("allRequestsSucceeded") is not True or manifest.get("failedResources") != []
            or not manifest.get("finishedAt") or manifest.get("safeToCutOver") is not False
            or not re.fullmatch(r"[0-9a-f]{64}", str(manifest.get("accountSubjectSHA256", "")))):
        raise InvalidExport("Snapshot is incomplete, unbound to an account, or from the wrong backend")
    entries = manifest.get("entries")
    if not isinstance(entries, list):
        raise InvalidExport("Missing manifest entries")
    resources, paths = {}, {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise InvalidExport("Invalid manifest entry")
        file = entry.get("file", "")
        if (not isinstance(file, str) or not re.fullmatch(r"[a-z0-9-]+\.json", file)
                or file == "manifest.json" or file[:-5] in resources):
            raise InvalidExport("Invalid or duplicate resource filename")
        raw, payload = read_json(root / file)
        if len(raw) != entry.get("bytes") or hashlib.sha256(raw).hexdigest() != entry.get("sha256"):
            raise InvalidExport("Snapshot checksum or byte count mismatch")
        name = file[:-5]
        if name == "profile":
            valid = isinstance(payload, dict) and isinstance(payload.get("id"), str) and bool(payload["id"])
        else:
            valid = isinstance(payload, list) and all(isinstance(row, dict) for row in payload)
        if not valid:
            raise InvalidExport("Resource has an invalid shape")
        resources[name], paths[name] = payload, entry.get("path")
    expected = dict(CORE)
    if not set(CORE).issubset(resources):
        raise InvalidExport("Snapshot omits a required account resource")
    seen = set()
    for row in resources["lists"]:
        raw_id, role = row.get("id"), row.get("viewer_role")
        if (not isinstance(raw_id, str) or not UUID.fullmatch(raw_id) or raw_id.lower() in seen
                or role not in {"owner", "editor", "viewer"} or not isinstance(row.get("items"), list)):
            raise InvalidExport("List ownership or identity is invalid")
        key = raw_id.lower()
        seen.add(key)
        expected[f"list-{key}-members"] = f"/v0/lists/{key}/members"
        if role == "owner":
            expected[f"list-{key}-share-codes"] = f"/v0/lists/{key}/share-codes"
    if paths != expected:
        raise InvalidExport("Export resource coverage or owner-only list metadata differs from manifest contract")
    return manifest, resources


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def indexed(rows, name):
    if name == "profile":
        return {"profile": rows}
    result = {}
    for row in rows:
        # Membership identity is the member, not a newly generated row id.
        key = row.get("user_id") if name.endswith("-members") else row.get("id")
        if name.endswith("-share-codes"):
            code = row.get("code")
            if not isinstance(code, str) or not code:
                raise InvalidExport("Missing share-code identity")
            # Codes grant access; only their digest may appear in the audit report.
            key = hashlib.sha256(code.encode()).hexdigest()
        if not isinstance(key, str) or not key or key in result:
            raise InvalidExport("Missing or repeated record identity; automatic reconciliation is unsafe")
        result[key] = row
    return result


def duplicate_places(rows):
    groups = {}
    for row in rows:
        key = None
        if row.get("google_place_id"):
            key = ("google_places", row["google_place_id"])
        elif row.get("provider_place_id") and row.get("location_provider"):
            key = (row["location_provider"], row["provider_place_id"])
        if key and all(isinstance(part, str) for part in key):
            groups.setdefault(key, []).append(row.get("id"))
    return [ids for ids in groups.values() if len(ids) > 1]


def compare(source, target):
    old_manifest, old = load_snapshot(source, LEGACY)
    new_manifest, new = load_snapshot(target, MANAGED)
    if old_manifest["accountSubjectSHA256"] != new_manifest["accountSubjectSHA256"]:
        raise InvalidExport("Exports belong to different authenticated accounts")
    diffs = {}
    for name in sorted(old.keys() | new.keys()):
        before = indexed(old[name], name) if name in old else {}
        after = indexed(new[name], name) if name in new else {}
        missing = sorted(before.keys() - after.keys())
        target_only = sorted(after.keys() - before.keys())
        conflicts = sorted(key for key in before.keys() & after.keys() if canonical(before[key]) != canonical(after[key]))
        diffs[name] = {"sourceCount": len(before), "targetCount": len(after),
                       "missingOnTarget": missing, "targetOnly": target_only, "conflicting": conflicts}
    equivalent = all(not (row["missingOnTarget"] or row["conflicting"] or row["targetOnly"]) for row in diffs.values())
    return {
        "source": LEGACY, "target": MANAGED,
        "accountSubjectSHA256": old_manifest["accountSubjectSHA256"],
        "apiSnapshotsEquivalent": equivalent,
        "safeToCutOver": False,
        "unverifiedCoverage": ["device-only records", "binary media", "resources without export routes",
                               "other accounts and shared-list ownership", "changes since sequential snapshots"],
        "resources": diffs,
        "sourceExactProviderDuplicates": duplicate_places(old["places"]),
        "sourceUnresolvedCandidateIDs": [row.get("id") for row in old["memory-candidates"]
                                         if row.get("status") in {"source_only", "needs_more_evidence"}],
        "policy": "Read-only audit: preserve target-only and conflicting data. No deletes, imports, inferred locations or automatic workflow settlements.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = compare(args.source, args.target)
        # Never overwrite an earlier audit, follow a symlink, or expose record IDs in stdout.
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump(report, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
    except (InvalidExport, OSError) as error:
        print(f"Account preservation audit failed ({type(error).__name__}); no cutover authorized.", file=sys.stderr)
        return 1
    print("Account comparison saved privately. API parity: " + str(report["apiSnapshotsEquivalent"]) + ". Cutover remains blocked pending complete data coverage and review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
