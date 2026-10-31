"""Offline export completeness controls; also run with Python -O."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile
from source_manifest import verify_source_manifest


class SourceManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'source'
        self.root.mkdir()
        self.payload = {'main.mbt': b'reviewed source', 'docs/中文.md': b'documentation'}
        for name, data in self.payload.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.state = {'head': 'a' * 40,
                      'files_sha256': {n: hashlib.sha256(d).hexdigest()
                                       for n, d in self.payload.items()}}
        self.save()

    def save(self):
        (self.root / 'SOURCE_STATE.json').write_text(json.dumps(self.state))

    def test_exact_file_set_and_sha256_commit(self):
        self.assertEqual(verify_source_manifest(self.root), self.state)
        self.state['head'] = 'b' * 64
        self.save()
        self.assertEqual(verify_source_manifest(self.root), self.state)

    def test_omitted_and_changed_source_is_not_ignored(self):
        self.state['files_sha256'].pop('main.mbt')
        self.save()
        (self.root / 'main.mbt').write_text('unchecked changed source')
        with self.assertRaisesRegex(ValueError, 'file set mismatch.*unlisted=.*main.mbt'):
            verify_source_manifest(self.root)

    def test_unlisted_payload_missing_file_and_hash_change(self):
        extra = self.root / 'injected.mbt'
        extra.write_text('not in manifest')
        with self.assertRaisesRegex(ValueError, 'file set mismatch'):
            verify_source_manifest(self.root)
        extra.unlink()
        path = self.root / 'main.mbt'
        path.unlink()
        with self.assertRaisesRegex(ValueError, 'file set mismatch.*missing=.*main.mbt'):
            verify_source_manifest(self.root)
        path.write_text('different')
        with self.assertRaisesRegex(ValueError, 'manifest mismatch: main.mbt'):
            verify_source_manifest(self.root)

    def test_empty_or_invalid_manifest_shape(self):
        for value in [{}, {'head': 'a' * 40, 'files_sha256': {}},
                      {'head': 'a' * 40, 'files_sha256': []}, [],
                      {**self.state, 'head': 'not-a-commit'}]:
            with self.subTest(value=value):
                (self.root / 'SOURCE_STATE.json').write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    verify_source_manifest(self.root)

    def test_unsafe_and_aliased_manifest_paths(self):
        for name in ['', '.', '..', '../outside', '/absolute', 'a//b',
                     'a/./b', 'a/../b', 'dir/', 'a\\b', 'C:/file', 'SOURCE_STATE.json']:
            with self.subTest(name=name):
                self.state['files_sha256'] = {name: 'a' * 64}
                self.save()
                with self.assertRaisesRegex(ValueError, 'unsafe source manifest path'):
                    verify_source_manifest(self.root)

    def test_invalid_sha256_is_rejected_before_file_reads(self):
        for digest in [None, 42, '0' * 63, 'G' * 64, 'A' * 64]:
            with self.subTest(digest=digest):
                self.state['files_sha256']['main.mbt'] = digest
                self.save()
                with self.assertRaisesRegex(ValueError, 'invalid source manifest SHA-256'):
                    verify_source_manifest(self.root)

    def test_duplicate_json_keys_are_not_silently_overwritten(self):
        for raw in ['{"head":"' + 'a' * 40 + '","head":"' + 'b' * 40 + '"}',
                    '{"files_sha256":{"main.mbt":"a","main.mbt":"b"}}']:
            with self.subTest(raw=raw):
                (self.root / 'SOURCE_STATE.json').write_text(raw)
                with self.assertRaisesRegex(ValueError, 'duplicate source manifest key'):
                    verify_source_manifest(self.root)

    def test_metadata_payload_directory_links_and_special_files_are_refused(self):
        outside = self.base / 'outside'
        outside.write_text('must not be consumed')
        for name in ['SOURCE_STATE.json', 'main.mbt']:
            path = self.root / name
            original = path.read_bytes()
            path.unlink()
            path.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, 'regular files'):
                verify_source_manifest(self.root)
            path.unlink()
            path.write_bytes(original)
        link = self.root / 'linked-dir'
        link.symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'linked directories'):
            verify_source_manifest(self.root)
        link.unlink()
        os.mkfifo(self.root / 'pipe')
        with self.assertRaisesRegex(ValueError, 'regular files'):
            verify_source_manifest(self.root)

    def test_actual_delivery_driver_stops_before_tools_on_missing_manifest_entry(self):
        import verify_delivery_consumer as driver
        self.state['files_sha256'].pop('main.mbt')
        self.save()
        archive = self.base / 'source.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            for path in self.root.rglob('*'):
                if path.is_file():
                    z.write(path, 'MoonODS/' + path.relative_to(self.root).as_posix())
        before = archive.read_bytes()
        output = self.base / 'output'
        argv = ['verify', '--archive', str(archive), '--sdk', str(self.base / 'sdk'),
                '--output', str(output)]
        with mock.patch('sys.argv', argv), mock.patch.object(driver.subprocess, 'run') as run, \
                mock.patch.object(driver.shutil, 'which', return_value='/usr/bin/node'), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(driver.main(), 1)
        run.assert_not_called()
        report = json.loads((output / 'consumer.json').read_text())
        self.assertEqual(report['status'], 'FAIL')
        self.assertIn('file set mismatch', report['error'])
        self.assertEqual(report['steps'], [])
        self.assertEqual(archive.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
