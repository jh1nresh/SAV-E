import json
from pathlib import Path
import stat
import tempfile
import unittest

import test_preservation as fixtures

audit = fixtures.audit
planner = fixtures.load('planner', 'plan-account-preservation.py')


class PlanTests(unittest.TestCase):
    snapshot = fixtures.PreservationTests.snapshot
    mutate_manifest = fixtures.PreservationTests.mutate_manifest

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def partial(self, path):
        def mutate(manifest):
            manifest.update(allRequestsSucceeded=False, failedResources=['lists'])
            manifest['entries'] = [e for e in manifest['entries'] if e['file'] != 'lists.json']
        self.mutate_manifest(path, mutate)
        (path / 'lists.json').unlink()

    def test_partial_snapshot_is_not_rewritten_or_treated_as_empty(self):
        old = self.snapshot('old', audit.LEGACY)
        new = self.snapshot('new', audit.MANAGED)
        self.partial(old)
        before = (old / 'manifest.json').read_bytes()
        report = planner.plan(old, new)
        self.assertEqual(before, (old / 'manifest.json').read_bytes())
        self.assertIsNone(report['resources']['lists']['sourceCount'])
        self.assertIn('lists', report['blockingCoverage'])
        self.assertFalse(report['safeToApply'])
        self.assertFalse(report['safeToCutOver'])
        with self.assertRaises(audit.InvalidExport):
            audit.compare(old, new)

    def test_only_missing_original_content_is_proposed_not_status_or_permissions(self):
        old = self.snapshot('old', audit.LEGACY, {'memory-captures': [
            {'id': 'c1', 'raw_text': 'original clue', 'source_url': 'https://example.test', 'status': 'resolved'}],
            'places': [{'id': 'p1', 'visibility': 'friends'}]})
        new = self.snapshot('new', audit.MANAGED, {'memory-captures': [
            {'id': 'c1', 'raw_text': None, 'source_url': '', 'status': 'investigating'}],
            'places': [{'id': 'p1', 'visibility': None}]})
        report = planner.plan(old, new)
        proposals = report['resources']['memory-captures']['sourceContentProposals']
        self.assertEqual({'raw_text', 'source_url'}, {p['field'] for p in proposals})
        self.assertTrue(all(p['requiresReview'] for p in proposals))
        expected = planner.digest(json.loads((new / 'memory-captures.json').read_text())[0])
        self.assertTrue(all(p['expectedTargetRowSHA256'] == expected for p in proposals))
        self.assertIn('status', report['resources']['memory-captures']['conflicts'][0]['fields'])
        self.assertEqual([], report['resources']['places']['sourceContentProposals'])

    def test_keeps_target_only_and_nonempty_content_and_unresolved_references(self):
        old = self.snapshot('old', audit.LEGACY, {'memory-captures': [{'id': 'c1', 'raw_text': 'old'}],
            'memory-candidates': [{'id': 'c2', 'workflow_run_id': 'unavailable-workflow', 'status': 'source_only'}]})
        new = self.snapshot('new', audit.MANAGED, {'memory-captures': [{'id': 'c1', 'raw_text': 'new'}, {'id': 'c3'}]})
        report = planner.plan(old, new)
        self.assertEqual([], report['resources']['memory-captures']['sourceContentProposals'])
        self.assertEqual(['c3'], report['resources']['memory-captures']['keepTargetOnly'])
        row = report['resources']['memory-candidates']['missingRecords'][0]
        self.assertEqual('source_only', row['source']['status'])
        self.assertEqual('unavailable-workflow', row['source']['workflow_run_id'])
        self.assertTrue(row['requiresReview'])

    def test_rejects_tamper_missing_resource_and_mixed_owner(self):
        new = self.snapshot('new', audit.MANAGED)
        old = self.snapshot('old', audit.LEGACY)
        self.partial(old)
        (old / 'places.json').write_text('[{"id":"tampered"}]')
        with self.assertRaises(planner.audit.InvalidExport): planner.plan(old, new)
        old2 = self.snapshot('old2', audit.LEGACY)
        self.partial(old2)
        self.mutate_manifest(old2, lambda m: m['entries'].pop())
        with self.assertRaises(planner.audit.InvalidExport): planner.plan(old2, new)
        old3 = self.snapshot('old3', audit.LEGACY, {'places': [{'id': 'p1', 'user_id': 'another-account'}]})
        with self.assertRaises(planner.audit.InvalidExport): planner.plan(old3, new)

    def test_account_identity_must_match_even_when_subject_hash_matches(self):
        old = self.snapshot('old', audit.LEGACY, {'profile': {'id': 'different-profile'}})
        new = self.snapshot('new', audit.MANAGED)
        with self.assertRaises(planner.audit.InvalidExport): planner.plan(old, new)

    def test_private_output_refuses_overwrite_or_symlink(self):
        file = self.root / 'plan.json'
        planner.write_plan(file, {'safeToApply': False})
        self.assertEqual(0o600, stat.S_IMODE(file.stat().st_mode))
        before = file.read_bytes()
        with self.assertRaises(FileExistsError): planner.write_plan(file, {})
        link = self.root / 'link.json'
        link.symlink_to(file)
        with self.assertRaises(FileExistsError): planner.write_plan(link, {})
        self.assertEqual(before, file.read_bytes())


if __name__ == '__main__':
    unittest.main()
