"""Offline guard tests only: no SDK download or installation."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('install_ci_sdk', ROOT / 'scripts/install-ci-sdk.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerGuards(unittest.TestCase):
    def test_lock_uses_this_projects_exact_release(self):
        lock = installer.checked_lock(ROOT / 'TOOLCHAIN.lock')
        self.assertEqual(lock['compiler'], '0.10.18+6c83a7f62')
        self.assertEqual(lock['sdk_sha256'], '0e4cde1ace98e8ef00552a937738b59c6901c4b8a004ebad71ea0e63688f63f1')
        self.assertEqual(lock['core_sha256'], '30a8ae1c1e1e8fde478ea742cbc928c8f4ae1f5c00090afe3f10c97be9e5da64')

    def test_origin_exactness(self):
        self.assertTrue(installer.official_url('https://cli.moonbitlang.com/a'))
        for bad in ('https://cli.moonbitlang.com.evil.test/a', 'http://cli.moonbitlang.com/a',
                    'https://user@cli.moonbitlang.com/a', 'https://cli.moonbitlang.com/a?b'):
            self.assertFalse(installer.official_url(bad))

    def test_destination_does_not_overwrite_or_leave_project(self):
        with self.assertRaises(ValueError):
            installer.destination(ROOT)
        with self.assertRaises(ValueError):
            installer.destination(ROOT.parent / 'outside-sdk')
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            with self.assertRaises(ValueError):
                installer.destination(Path(tmp))
            dest = Path(tmp) / 'new-sdk'
            self.assertEqual(installer.destination(dest), dest)
            self.assertFalse(dest.exists())

    def test_drift_and_bad_hash_rejected(self):
        original = json.loads((ROOT / 'TOOLCHAIN.lock').read_text())
        for key, value in [('sdk_url', 'https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz'),
                           ('core_sha256', 'wrong')]:
            with tempfile.TemporaryDirectory() as tmp:
                changed = {**original, key: value}
                path = Path(tmp) / 'lock.json'
                path.write_text(json.dumps(changed))
                with self.assertRaises(ValueError):
                    installer.checked_lock(path)


class ExtractionGuards(unittest.TestCase):
    def test_synthetic_0664_tools_are_restored(self):
        import io, os, sys, tarfile
        from unittest import mock
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            dest = Path(tmp) / 'sdk'
            def download(url, path, digest):
                with tarfile.open(path, 'w:gz') as archive:
                    names = ['bin/' + n for n in installer.TOOLS] if '/binaries/' in url else ['core/marker']
                    for name in names:
                        item = tarfile.TarInfo(name); item.size = 1; item.mode = 0o664
                        archive.addfile(item, io.BytesIO(b'x'))
            with mock.patch.object(sys, 'argv', ['installer', '--dest', str(dest)]), \
                 mock.patch.object(installer, 'download', side_effect=download), \
                 mock.patch.object(installer.subprocess, 'check_output', return_value='v0.10.18+6c83a7f62 (mock)'), \
                 mock.patch.object(installer.subprocess, 'run') as run:
                installer.main()
            for name in installer.TOOLS:
                self.assertTrue(os.access(dest / 'bin' / name, os.X_OK))
            self.assertEqual(run.call_args.kwargs['cwd'], dest / 'lib/core')
            self.assertEqual(run.call_args.kwargs['env']['MOON_HOME'], str(dest))

    def test_wrong_download_hash(self):
        import io
        from unittest import mock
        class Response(io.BytesIO):
            url = 'https://cli.moonbitlang.com/test'
        with tempfile.TemporaryDirectory() as tmp:
            opener = mock.Mock()
            opener.open.return_value = Response(b'wrong bytes')
            with mock.patch.object(installer.urllib.request, 'build_opener', return_value=opener):
                with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
                    installer.download(Response.url, Path(tmp) / 'archive', '0' * 64)

    def test_archive_traversal_is_rejected(self):
        import io, sys, tarfile
        from unittest import mock
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            dest = Path(tmp) / 'sdk'
            def download(url, path, digest):
                with tarfile.open(path, 'w:gz') as archive:
                    item = tarfile.TarInfo('../escaped'); item.size = 1
                    archive.addfile(item, io.BytesIO(b'x'))
            with mock.patch.object(sys, 'argv', ['installer', '--dest', str(dest)]), \
                 mock.patch.object(installer, 'download', side_effect=download):
                with self.assertRaises(tarfile.FilterError):
                    installer.main()
            self.assertFalse((Path(tmp) / 'escaped').exists())


if __name__ == '__main__':
    unittest.main()
