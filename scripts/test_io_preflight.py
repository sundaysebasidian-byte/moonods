"""Owned temporary fixtures: validation failures must not mutate destinations."""
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

from restore_deps import restore
from verify_delivery_consumer import unpack


class PreflightTests(unittest.TestCase):
    def dependency(self, root, contents, archive_name='dep.zip'):
        archive = root / archive_name
        archive.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive, 'w') as z:
            for name, data in contents.items():
                z.writestr(name, data)
        lock = {'dep': {'module': 'vendor/dep', 'version': 'test',
                       'archive': archive_name,
                       'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                       'files_sha256': {name: hashlib.sha256(data).hexdigest()
                                        for name, data in contents.items()}}}
        (root / 'DEPENDENCIES.lock.json').write_text(json.dumps(lock))
        return archive, root / '.mooncakes/vendor/dep'

    def test_dependency_file_parent_collision_before_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _, target = self.dependency(root, {'early': b'changed', 'x': b'x', 'x/y': b'y'})
            with self.assertRaises(ValueError):
                restore(root)
            self.assertFalse(target.exists())

    def test_dependency_existing_parent_file_preserves_earlier_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _, target = self.dependency(root, {'early': b'changed', 'x': b'x', 'x/y': b'y'})
            target.mkdir(parents=True)
            (target / 'early').write_bytes(b'KEEP')
            (target / 'x').write_bytes(b'KEEP_PARENT')
            with self.assertRaises(ValueError):
                restore(root)
            self.assertEqual((target / 'early').read_bytes(), b'KEEP')
            self.assertEqual((target / 'x').read_bytes(), b'KEEP_PARENT')

    def test_dependency_archive_must_not_be_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive, target = self.dependency(root, {'early': b'changed', 'input.zip': b'destroyed'},
                                              '.mooncakes/vendor/dep/input.zip')
            before = archive.read_bytes()
            with self.assertRaises(ValueError):
                restore(root)
            self.assertEqual(archive.read_bytes(), before)
            self.assertFalse((target / 'early').exists())

    def test_unpack_file_parent_collisions_before_destination(self):
        for items in ([('early', b'x'), ('x', b'x'), ('x/y', b'y')],
                      [('early', b'x'), ('x/y', b'y'), ('x', b'x')],
                      [('early', b'x'), ('x/', b''), ('x', b'x')]):
            with self.subTest(items=items), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                archive = root / 'input.zip'
                with zipfile.ZipFile(archive, 'w') as z:
                    for name, data in items:
                        z.writestr('MoonODS/' + name, data)
                with self.assertRaises(ValueError):
                    unpack(archive, root / 'output', 'MoonODS/')
                self.assertFalse((root / 'output').exists())

    def test_unpack_special_entries_before_destination(self):
        for mode in (stat.S_IFIFO, stat.S_IFCHR, stat.S_IFSOCK):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                archive = root / 'input.zip'
                with zipfile.ZipFile(archive, 'w') as z:
                    z.writestr('early', b'x')
                    entry = zipfile.ZipInfo('special')
                    entry.create_system = 3
                    entry.external_attr = (mode | 0o600) << 16
                    z.writestr(entry, b'x')
                with self.assertRaises(ValueError):
                    unpack(archive, root / 'output')
                self.assertFalse((root / 'output').exists())

    def test_unpack_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'input.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('MoonODS/', b'')
                z.writestr('MoonODS/sub/', b'')
                z.writestr('MoonODS/sub/file', b'content')
            unpack(archive, root / 'output', 'MoonODS/')
            self.assertEqual((root / 'output/sub/file').read_bytes(), b'content')


if __name__ == '__main__':
    unittest.main()
