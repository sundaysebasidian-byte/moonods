"""Synthetic offline integrity tests. Each test owns an isolated temporary tree."""
import hashlib
import json
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile
from restore_deps import restore
from verify_deps import verify


class DependencyIntegrity(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'project'
        self.root.mkdir()
        self.archive = self.root / 'dep.zip'
        self.target = self.root / '.mooncakes/vendor/dep'
        self.contents = {'main.mbt': b'original', 'sub/file.mbt': b'child'}
        self.make_archive(self.contents)

    def make_archive(self, entries):
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, data in entries.items():
                z.writestr(name, data)
        self.lock = {'dep': {'module': 'vendor/dep', 'version': 'test',
                            'archive': 'dep.zip',
                            'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                            'files_sha256': {n: hashlib.sha256(d).hexdigest()
                                             for n, d in self.contents.items()}}}
        self.save_lock()

    def save_lock(self):
        (self.root / 'DEPENDENCIES.lock.json').write_text(json.dumps(self.lock))

    def test_restore_verify_idempotent(self):
        self.assertEqual(restore(self.root), verify(self.root))
        before = {p.relative_to(self.target): p.read_bytes()
                  for p in self.target.rglob('*') if p.is_file()}
        restore(self.root)
        self.assertEqual(before, {p.relative_to(self.target): p.read_bytes()
                                 for p in self.target.rglob('*') if p.is_file()})

    def test_archive_digest_mismatch_before_write(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'tamper')
        with self.assertRaisesRegex(ValueError, 'archive mismatch'):
            restore(self.root)
        self.assertFalse(self.target.exists())

    def test_verify_archive_digest(self):
        restore(self.root)
        self.archive.write_bytes(self.archive.read_bytes() + b'tamper')
        with self.assertRaisesRegex(ValueError, 'archive mismatch'):
            verify(self.root)

    def test_modified_source(self):
        restore(self.root)
        (self.target / 'main.mbt').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'source mismatch'):
            verify(self.root)

    def test_extra_file(self):
        restore(self.root)
        (self.target / 'injected.mbt').write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'file set mismatch'):
            verify(self.root)
        with self.assertRaisesRegex(ValueError, 'unexpected installed'):
            restore(self.root)
        self.assertEqual((self.target / 'injected.mbt').read_bytes(), b'extra')

    def test_missing_file(self):
        restore(self.root)
        (self.target / 'main.mbt').unlink()
        with self.assertRaisesRegex(ValueError, 'file set mismatch'):
            verify(self.root)

    def test_target_symlink_escape(self):
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        (outside / 'main.mbt').write_bytes(b'sentinel')
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(outside, target_is_directory=True)
        for operation in (restore, verify):
            with self.assertRaisesRegex(ValueError, 'symlink'):
                operation(self.root)
        self.assertEqual((outside / 'main.mbt').read_bytes(), b'sentinel')
        self.assertEqual(len(list(outside.iterdir())), 1)

    def test_file_symlink_escape(self):
        restore(self.root)
        outside = Path(self.tmp.name) / 'sentinel'
        outside.write_bytes(b'outside')
        (self.target / 'main.mbt').unlink()
        (self.target / 'main.mbt').symlink_to(outside)
        for operation in (restore, verify):
            with self.assertRaisesRegex(ValueError, 'symlink'):
                operation(self.root)
        self.assertEqual(outside.read_bytes(), b'outside')

    def test_archive_traversal_preflight(self):
        self.make_archive({**self.contents, '../escape': b'no'})
        with self.assertRaisesRegex(ValueError, 'unsafe dependency path'):
            restore(self.root)
        self.assertFalse(self.target.exists())

    def test_archive_member_mismatch_preflight(self):
        self.make_archive({'main.mbt': b'corrupt', 'sub/file.mbt': b'child'})
        with self.assertRaisesRegex(ValueError, 'member digest mismatch'):
            restore(self.root)
        self.assertFalse(self.target.exists())

    def test_archive_symlink(self):
        with zipfile.ZipFile(self.archive, 'w') as z:
            entry = zipfile.ZipInfo('main.mbt')
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(entry, b'original')
        self.lock['dep']['sha256'] = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.save_lock()
        with self.assertRaisesRegex(ValueError, 'archive symlink'):
            restore(self.root)
        self.assertFalse(self.target.exists())

    def test_lock_module_traversal(self):
        self.lock['dep']['module'] = '../outside'
        self.save_lock()
        with self.assertRaisesRegex(ValueError, 'unsafe dependency path'):
            restore(self.root)


if __name__ == '__main__':
    unittest.main()
