import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load('audit', 'compare-account-exports.py')
release = load('release', 'verify-release-api.py')


class PreservationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def snapshot(self, name, origin, updates=None, subject='same-account'):
        directory = self.root / name
        directory.mkdir()
        data = {key: [] for key in audit.CORE}
        data['profile'] = {'id': 'account-id', 'display_name': 'fixture'}
        data.update(updates or {})
        paths = dict(audit.CORE)
        for row in data['lists']:
            key = row['id']
            paths[f'list-{key}-members'] = f'/v0/lists/{key}/members'
            data.setdefault(f'list-{key}-members', [])
            if row['viewer_role'] == 'owner':
                paths[f'list-{key}-share-codes'] = f'/v0/lists/{key}/share-codes'
                data.setdefault(f'list-{key}-share-codes', [])
        entries = []
        for key, value in data.items():
            raw = json.dumps(value).encode()
            file = key + '.json'
            (directory / file).write_bytes(raw)
            entries.append({'file': file, 'path': paths[key], 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        manifest = {'source': origin, 'accountSubjectSHA256': hashlib.sha256(subject.encode()).hexdigest(),
                    'finishedAt': '2026-09-17T00:00:00Z', 'allRequestsSucceeded': True,
                    'failedResources': [], 'safeToCutOver': False, 'entries': entries}
        (directory / 'manifest.json').write_text(json.dumps(manifest))
        return directory

    def mutate_manifest(self, path, operation):
        file = path / 'manifest.json'
        manifest = json.loads(file.read_text())
        operation(manifest)
        file.write_text(json.dumps(manifest))

    def test_equal_api_data_never_proves_cutover(self):
        old = self.snapshot('old', audit.LEGACY)
        new = self.snapshot('new', audit.MANAGED)
        report = audit.compare(old, new)
        self.assertTrue(report['apiSnapshotsEquivalent'])
        self.assertFalse(report['safeToCutOver'])
        self.assertIn('binary media', report['unverifiedCoverage'])

    def test_preserves_different_target_data_and_finds_old_duplicates(self):
        before = [{'id': 'p1', 'name': 'Cafe', 'google_place_id': 'same'},
                  {'id': 'p2', 'name': 'Cafe', 'google_place_id': 'same'}]
        old = self.snapshot('old', audit.LEGACY, {'places': before,
                            'memory-candidates': [{'id': 'c1', 'status': 'source_only'}]})
        new = self.snapshot('new', audit.MANAGED, {'places': [{'id': 'p1', 'name': 'Newer note'}, {'id': 'p3'}]})
        report = audit.compare(old, new)
        self.assertEqual(report['resources']['places']['missingOnTarget'], ['p2'])
        self.assertEqual(report['resources']['places']['targetOnly'], ['p3'])
        self.assertEqual(report['resources']['places']['conflicting'], ['p1'])
        self.assertEqual(report['sourceExactProviderDuplicates'], [['p1', 'p2']])
        self.assertEqual(report['sourceUnresolvedCandidateIDs'], ['c1'])
        self.assertEqual(json.loads((old / 'places.json').read_text()), before)

    def test_account_change_is_blocked(self):
        old = self.snapshot('old', audit.LEGACY)
        new = self.snapshot('new', audit.MANAGED, subject='different')
        with self.assertRaises(audit.InvalidExport): audit.compare(old, new)

    def test_missing_checksum_failure_or_interrupted_snapshot_is_blocked(self):
        variants = [lambda m: m.update(allRequestsSucceeded=False),
                    lambda m: m.update(failedResources=['places']),
                    lambda m: m.pop('finishedAt'), lambda m: m['entries'].pop(),
                    lambda m: m['entries'][0].update(sha256='0' * 64),
                    lambda m: m['entries'].append(copy.deepcopy(m['entries'][0])),
                    lambda m: m['entries'][0].update(file='../private.json')]
        for index, mutate in enumerate(variants):
            with self.subTest(index=index):
                old = self.snapshot(str(index), audit.LEGACY)
                self.mutate_manifest(old, mutate)
                with self.assertRaises(audit.InvalidExport): audit.load_snapshot(old, audit.LEGACY)

    def test_symlink_is_not_read(self):
        old = self.snapshot('old', audit.LEGACY)
        file = old / 'places.json'
        file.unlink()
        file.symlink_to(old / 'trips.json')
        with self.assertRaises(audit.InvalidExport): audit.load_snapshot(old, audit.LEGACY)

    def test_owner_metadata_required_but_viewer_cannot_invent_owner_rights(self):
        key = '11111111-1111-4111-8111-111111111111'
        owner = self.snapshot('owner', audit.LEGACY, {'lists': [{'id': key, 'viewer_role': 'owner', 'items': []}]})
        self.mutate_manifest(owner, lambda m: m['entries'].pop())
        with self.assertRaises(audit.InvalidExport): audit.load_snapshot(owner, audit.LEGACY)
        viewer = self.snapshot('viewer', audit.LEGACY, {'lists': [{'id': key, 'viewer_role': 'viewer', 'items': []}]})
        _, data = audit.load_snapshot(viewer, audit.LEGACY)
        self.assertNotIn(f'list-{key}-share-codes', data)

    def test_duplicate_or_missing_record_ids_are_not_silently_lost(self):
        for rows in [[{'id': 'x'}, {'id': 'x'}], [{'name': 'unknown'}]]:
            with self.assertRaises(audit.InvalidExport): audit.indexed(rows, 'places')

    def test_owner_share_codes_use_private_stable_identity(self):
        key = '11111111-1111-4111-8111-111111111111'
        resource = f'list-{key}-share-codes'
        code = {'code': 'fixture-invitation-secret', 'role': 'viewer',
                'url': 'https://example.invalid/?c=fixture-invitation-secret',
                'expires_at': None, 'created_at': '2026-09-17T00:00:00Z'}
        data = {'lists': [{'id': key, 'viewer_role': 'owner', 'items': []}], resource: [code]}
        old = self.snapshot('old', audit.LEGACY, data)
        same = self.snapshot('same', audit.MANAGED, data)
        self.assertTrue(audit.compare(old, same)['apiSnapshotsEquivalent'])
        different = copy.deepcopy(data)
        different[resource][0]['role'] = 'editor'
        changed = self.snapshot('changed', audit.MANAGED, different)
        report = audit.compare(old, changed)
        digest = hashlib.sha256(code['code'].encode()).hexdigest()
        self.assertEqual(report['resources'][resource]['conflicting'], [digest])
        missing = self.snapshot('missing', audit.MANAGED, {**data, resource: []})
        report = audit.compare(old, missing)
        self.assertEqual(report['resources'][resource]['missingOnTarget'], [digest])
        self.assertNotIn(code['code'], json.dumps(report))
        self.assertNotIn(code['url'], json.dumps(report))
        for rows in [[code, code], [{'code': None}], [{}]]:
            with self.assertRaises(audit.InvalidExport): audit.indexed(rows, resource)

    def test_api_origin_mismatch_and_credential_urls_fail(self):
        with self.assertRaises(ValueError): release.verify({'SAVE_API_URL': audit.LEGACY}, audit.MANAGED)
        with self.assertRaises(ValueError): release.verify({'SAVE_API_URL': audit.MANAGED, 'WANDERLY_API_URL': audit.LEGACY}, audit.MANAGED)
        for bad in [None, '', 'http://save-backend-production.up.railway.app', audit.MANAGED+'?token=secret', audit.MANAGED+'/path', 'https://user:password@save-backend-production.up.railway.app']:
            with self.subTest(bad=bad), self.assertRaises(ValueError): release.verify({'SAVE_API_URL': bad}, audit.MANAGED)
        self.assertEqual(release.verify({'SAVE_API_URL': audit.MANAGED+'/'}, audit.MANAGED), audit.MANAGED)


if __name__ == '__main__':
    unittest.main()
