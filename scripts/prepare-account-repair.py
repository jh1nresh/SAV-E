#!/usr/bin/env python3
"""Prepare a bounded historical-record repair from verified account exports.

Does not connect to a database or authorize a backend cutover. Social settings,
existing decisions, coordinates, workflows and credit balances are not copied.
"""
import argparse
import copy
import json
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("preservation", Path(__file__).with_name("plan-account-preservation.py"))
preservation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preservation)

TABLES = {"places": "places", "memory-captures": "captures", "memory-candidates": "place_candidates"}


def prepare(source, target):
    proposal = preservation.plan(source, target)
    _, old, _ = preservation.partial_source(source)
    _, new = preservation.audit.load_snapshot(target, preservation.audit.MANAGED)
    owner = old["profile"]["id"]
    captures = {r["id"]: r for r in old["memory-captures"]}
    places = {r["id"]: r for r in old["places"]}
    # A candidate is owned through its capture; never infer ownership from an ID.
    for row in [*old["places"], *old["memory-captures"]]:
        if row.get("user_id") != owner:
            raise ValueError("Explicit record ownership required")
    for row in old["memory-candidates"]:
        if row.get("capture_id") not in captures:
            raise ValueError("Missing owned capture")
        if row.get("place_id") and row["place_id"] not in places:
            raise ValueError("Missing owned place")
    inserts = {}
    place_merges = []
    merges_by_target = {}
    target_places = {row['google_place_id']: row for row in new['places'] if row.get('google_place_id')}
    for resource, table in TABLES.items():
        rows = []
        for item in proposal["resources"][resource]["missingRecords"]:
            row = copy.deepcopy(item["source"])
            if table == 'places' and row.get('google_place_id') in target_places:
                original = target_places[row['google_place_id']]
                current = copy.deepcopy(original)
                previous = merges_by_target.get(current['id'])
                if previous:
                    current.update(previous['patch'])
                if current.get('user_id') != owner:
                    raise ValueError('Foreign duplicate place')
                # Do not silently strand trip or candidate references. This
                # bounded repair handles only independent duplicate saves.
                if (row['id'] in json.dumps(old['trips'])
                        or any(c['source'].get('place_id') == row['id'] for c in proposal['resources']['memory-candidates']['missingRecords'])):
                    raise ValueError('Duplicate place has references requiring reconciliation')
                patch = {}
                source_note, current_note = row.get('note') or '', current.get('note') or ''
                if source_note and source_note not in current_note:
                    patch['note'] = '\n\n'.join(note for note in [current_note, source_note] if note)
                photos = list(dict.fromkeys([*(current.get('business_photo_urls') or []), *(row.get('business_photo_urls') or [])]))
                if photos != (current.get('business_photo_urls') or []): patch['business_photo_urls'] = photos
                if row['created_at'] < current['created_at']: patch['created_at'] = row['created_at']
                if previous:
                    previous['sourceIDs'].append(row['id'])
                    previous['patch'].update(patch)
                    previous['expected'].update({key: original.get(key) for key in patch})
                else:
                    expected = {key: original.get(key) for key in ['id', 'user_id', 'google_place_id', *patch]}
                    merge = {'sourceIDs': [row['id']], 'expected': expected, 'patch': patch}
                    place_merges.append(merge)
                    merges_by_target[current['id']] = merge
                continue
            if table == "place_candidates" and row.get("workflow_run_id"):
                if not isinstance(row.get("evidence"), list):
                    raise ValueError("Candidate evidence must be an array")
                row["evidence"].append({"legacy_workflow_provenance": {
                    "origin": preservation.audit.LEGACY,
                    "workflow_run_id": row["workflow_run_id"],
                    "migration_mode": "historical_record_only",
                }})
                row["workflow_run_id"] = None
            rows.append(row)
        inserts[table] = rows
    # Abort instead of silently ignoring additional missing core resources.
    for name in ("trips", "memory-preferences", "recommendation-outcomes"):
        if proposal["resources"][name]["missingRecords"]:
            raise ValueError("Additional core resource requires a separate repair")
    return {
        "version": 1, "mode": "historical_account_repair", "owner": owner,
        "sourceManifestSHA256": proposal["sourceManifestSHA256"],
        "targetManifestSHA256": proposal["targetManifestSHA256"],
        "inserts": inserts,
        "placeMerges": place_merges,
        "captureFills": proposal["resources"]["memory-captures"]["sourceContentProposals"],
        "expectedTarget": {table: new[resource] for resource, table in TABLES.items()},
        "safeToCutOver": False,
        "limitations": ["Social settings must be rebuilt with explicit consent", "Device-only data remains on the original installation",
                        "Historical workflow references are inert provenance, not transferred settlement", "Other accounts are outside this repair"],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        preservation.write_plan(args.output, prepare(args.source, args.target))
    except (OSError, ValueError, TypeError, KeyError, preservation.audit.InvalidExport):
        raise SystemExit("Repair preparation failed; no data changed.")
    print("Private historical repair prepared; no data changed or cutover authorized.")
