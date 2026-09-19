import unittest
import tempfile
from pathlib import Path

import test_plan
import test_preservation as fixtures

repair = fixtures.load('repair', 'prepare-account-repair.py')


class RepairTests(unittest.TestCase):
    snapshot = fixtures.PreservationTests.snapshot
    mutate_manifest = fixtures.PreservationTests.mutate_manifest
    partial = test_plan.PlanTests.partial

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def pair(self, candidate=None, capture_owner='fixture-account'):
        old = self.snapshot('old', fixtures.audit.LEGACY, {
            'profile': {'id': 'fixture-account'},
            'places': [{'id': 'place', 'user_id': 'fixture-account'}],
            'memory-captures': [{'id': 'capture', 'user_id': capture_owner, 'raw_text': 'clue'}],
            'memory-candidates': [candidate or {'id': 'candidate', 'capture_id': 'capture',
                'workflow_run_id': 'old-run', 'status': 'source_only', 'evidence': [{'text': 'clue'}]}],
        })
        new = self.snapshot('new', fixtures.audit.MANAGED, {'profile': {'id': 'fixture-account'},
            'places': [], 'memory-captures': [], 'memory-candidates': []})
        self.partial(old)
        return old, new

    def test_historical_reference_retains_source_and_does_not_promote_state(self):
        old, new = self.pair()
        before = (old / 'memory-candidates.json').read_bytes()
        bundle = repair.prepare(old, new)
        row = bundle['inserts']['place_candidates'][0]
        self.assertEqual('source_only', row['status'])
        self.assertIsNone(row['workflow_run_id'])
        self.assertEqual('old-run', row['evidence'][-1]['legacy_workflow_provenance']['workflow_run_id'])
        self.assertEqual({'text': 'clue'}, row['evidence'][0])
        self.assertEqual(before, (old / 'memory-candidates.json').read_bytes())
        self.assertFalse(bundle['safeToCutOver'])

    def test_rejects_candidate_foreign_dependencies(self):
        for field, value in [('capture_id', 'foreign-capture'), ('place_id', 'foreign-place')]:
            with self.subTest(field=field):
                self.setUp()
                row = {'id': 'candidate', 'capture_id': 'capture', 'evidence': []}
                row[field] = value
                old, new = self.pair(row)
                with self.assertRaises(ValueError): repair.prepare(old, new)

    def test_missing_owner_is_not_assumed(self):
        old, new = self.pair(capture_owner=None)
        with self.assertRaises((ValueError, repair.preservation.audit.InvalidExport)):
            repair.prepare(old, new)

    def test_duplicate_venue_preserves_both_notes_photos_and_earliest_date(self):
        old = self.snapshot('old', fixtures.audit.LEGACY, {'profile': {'id': 'fixture-account'},
            'places': [{'id': 'old-place', 'user_id': 'fixture-account', 'google_place_id': 'provider',
                        'note': 'Old note', 'business_photo_urls': ['old-photo'], 'created_at': '2026-01-01T00:00:00Z'}],
            'memory-captures': [], 'memory-candidates': []})
        new = self.snapshot('new', fixtures.audit.MANAGED, {'profile': {'id': 'fixture-account'},
            'places': [{'id': 'canonical', 'user_id': 'fixture-account', 'google_place_id': 'provider',
                        'note': 'New note', 'business_photo_urls': ['new-photo'], 'created_at': '2026-02-01T00:00:00Z'}],
            'memory-captures': [], 'memory-candidates': []})
        self.partial(old)
        bundle = repair.prepare(old, new)
        self.assertEqual([], bundle['inserts']['places'])
        self.assertEqual({'note': 'New note\n\nOld note', 'business_photo_urls': ['new-photo', 'old-photo'],
                          'created_at': '2026-01-01T00:00:00Z'}, bundle['placeMerges'][0]['patch'])


if __name__ == '__main__': unittest.main()
