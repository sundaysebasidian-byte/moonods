"""Offline SDK trust-boundary probes; no tool executes and no network is contacted."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock
import urllib.request

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('installer_boundaries', SOURCE / 'scripts/install-ci-sdk.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
RECEIPTS = []


class SDKBoundaries(unittest.TestCase):
    @contextlib.contextmanager
    def case(self, surface, name):
        record = {'surface': surface, 'case': name, 'passed': False}
        RECEIPTS.append(record)
        try:
            yield
            record['passed'] = True
        except Exception as exc:
            record['error'] = repr(exc)
            raise

    def test_download_stream_origin_and_exclusive_output(self):
        class Response(io.BytesIO):
            url = 'https://cli.moonbitlang.com/synthetic'
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for name, url in [('foreign-final', 'https://evil.invalid/a'),
                              ('http-final', 'http://cli.moonbitlang.com/a')]:
                with self.case(26, name):
                    response = Response(b'bytes'); response.url = url
                    opener = mock.Mock(); opener.open.return_value = response
                    with mock.patch.object(installer.urllib.request, 'build_opener', return_value=opener):
                        with self.assertRaisesRegex(ValueError, 'unexpected response URL'):
                            installer.download(Response.url, root / name, hashlib.sha256(b'bytes').hexdigest())
                    self.assertEqual((root / name).read_bytes(), b'')
            with self.case(26, 'exclusive-existing-output'):
                output = root / 'existing'; output.write_bytes(b'KEEP')
                opener = mock.Mock(); opener.open.return_value = Response(b'bytes')
                with mock.patch.object(installer.urllib.request, 'build_opener', return_value=opener):
                    with self.assertRaises(FileExistsError):
                        installer.download(Response.url, output, hashlib.sha256(b'bytes').hexdigest())
                self.assertEqual(output.read_bytes(), b'KEEP')
            with self.case(26, 'chunked-exact-digest'):
                opener = mock.Mock(); opener.open.return_value = Response(b'a' * 1048577)
                output = root / 'complete'
                with mock.patch.object(installer.urllib.request, 'build_opener', return_value=opener):
                    installer.download(Response.url, output, hashlib.sha256(b'a' * 1048577).hexdigest())
                self.assertEqual(output.stat().st_size, 1048577)
            with self.case(26, '512MiB-stream-ceiling-without-disk-allocation'):
                class Stream:
                    url = Response.url
                    count = 0
                    def __enter__(self): return self
                    def __exit__(self, *args): return False
                    def read(self, size):
                        self.count += 1
                        return b'x' * size
                class Sink:
                    size = 0
                    mode = None
                    def open(self, mode): self.mode = mode; return self
                    def __enter__(self): return self
                    def __exit__(self, *args): return False
                    def write(self, data): self.size += len(data)
                stream, sink = Stream(), Sink()
                opener = mock.Mock(); opener.open.return_value = stream
                with mock.patch.object(installer.urllib.request, 'build_opener', return_value=opener):
                    with self.assertRaisesRegex(ValueError, 'bounded download ceiling'):
                        installer.download(Response.url, sink, '0' * 64)
                self.assertEqual(stream.count, 513)
                self.assertEqual(sink.size, 512 * 1024 * 1024)
                self.assertEqual(sink.mode, 'xb')
            for url in ['http://cli.moonbitlang.com/x', 'https://user@cli.moonbitlang.com/x',
                        'https://cli.moonbitlang.com:443/x', 'https://cli.moonbitlang.com/x#frag']:
                with self.case(26, 'redirect-' + url):
                    with self.assertRaises(ValueError):
                        installer.OfficialRedirect().redirect_request(
                            urllib.request.Request(Response.url), None, 302, '', {}, url)

    def synthetic_archive(self, part, path, variant='valid'):
        with tarfile.open(path, 'w:gz') as archive:
            names = ['bin/' + name for name in installer.TOOLS] if part == 'sdk' else ['core/marker']
            if part == 'sdk' and variant in ('missing', 'internal-symlink', 'internal-hardlink'):
                names.remove('bin/moon')
            if part == 'core' and variant == 'workspace-exists': names.append('core/moon.work')
            for name in names:
                item = tarfile.TarInfo(name); item.size = 1
                item.mode = 0o4777 if variant == 'setuid' else 0o664
                archive.addfile(item, io.BytesIO(b'x'))
            if part == 'sdk' and variant in ('external-symlink', 'external-hardlink', 'fifo', 'internal-symlink', 'internal-hardlink'):
                item = tarfile.TarInfo('bin/moon' if variant.startswith('internal') else 'unsafe')
                item.type = tarfile.FIFOTYPE if variant == 'fifo' else tarfile.LNKTYPE if 'hardlink' in variant else tarfile.SYMTYPE
                item.linkname = ('bin/moonc' if 'hardlink' in variant else 'moonc') if variant.startswith('internal') else '../outside'
                archive.addfile(item)

    @contextlib.contextmanager
    def project(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / 'project'; root.mkdir()
            (root / 'TOOLCHAIN.lock').write_bytes((SOURCE / 'TOOLCHAIN.lock').read_bytes())
            (root / 'sentinel').write_bytes(b'KEEP')
            with mock.patch.object(installer, 'ROOT', root): yield root, root / 'sdk'

    def call_main(self, dest, download, version='v0.10.18+6c83a7f62 (synthetic)', bundle_error=None):
        with mock.patch.object(sys, 'argv', ['installer', '--dest', str(dest)]), \
             mock.patch.object(installer, 'download', side_effect=download), \
             mock.patch.object(installer.subprocess, 'check_output', return_value=version) as compiler, \
             mock.patch.object(installer.subprocess, 'run', side_effect=bundle_error) as bundle, \
             contextlib.redirect_stdout(io.StringIO()):
            error = None
            try: installer.main()
            except Exception as exc: error = exc
            return error, compiler.call_count, bundle.call_count

    def test_both_archives_validate_before_destination(self):
        for failed in ['sdk', 'core']:
            with self.case(27, 'failure-' + failed), self.project() as (root, dest):
                calls = []
                def download(url, path, digest):
                    part = 'sdk' if '/binaries/' in url else 'core'; calls.append(part)
                    if part == failed: raise ValueError('synthetic digest mismatch')
                    self.synthetic_archive(part, path)
                error, compiler, bundle = self.call_main(dest, download)
                self.assertIsInstance(error, ValueError)
                self.assertEqual(calls, ['sdk'] if failed == 'sdk' else ['sdk', 'core'])
                self.assertFalse(dest.exists()); self.assertEqual((compiler, bundle), (0, 0))
                self.assertEqual((root / 'sentinel').read_bytes(), b'KEEP')
        with self.case(27, 'positive-two-archive-flow'), self.project() as (root, dest):
            calls = []
            def download(url, path, digest):
                part = 'sdk' if '/binaries/' in url else 'core'; calls.append(part); self.synthetic_archive(part, path)
            error, compiler, bundle = self.call_main(dest, download)
            self.assertIsNone(error); self.assertEqual(calls, ['sdk', 'core'])
            self.assertEqual((compiler, bundle), (1, 1)); self.assertTrue((dest / 'lib/core/marker').exists())

    def test_destination_aliases_and_intervening_creation(self):
        with self.project() as (root, dest):
            outside = root.parent / 'outside'; outside.mkdir()
            (root / 'external').symlink_to(outside, target_is_directory=True)
            (root / 'self').symlink_to(root, target_is_directory=True)
            (root / 'dangling').symlink_to(root.parent / 'not-created', target_is_directory=True)
            for name in ['external/sdk', 'self', 'dangling/sdk']:
                with self.case(28, name):
                    with self.assertRaises(ValueError): installer.destination(root / name)
            internal = root / 'internal'; internal.mkdir(); (root / 'alias').symlink_to(internal, target_is_directory=True)
            with self.case(28, 'internal-parent-canonical'):
                self.assertEqual(installer.destination(root / 'alias/new'), internal / 'new')
                self.assertFalse((internal / 'new').exists())
        with self.case(28, 'intervening-destination-creation'), self.project() as (root, dest):
            def download(url, path, digest):
                part = 'sdk' if '/binaries/' in url else 'core'; self.synthetic_archive(part, path)
                if part == 'core': dest.mkdir(); (dest / 'other-owner').write_bytes(b'KEEP')
            error, compiler, bundle = self.call_main(dest, download)
            self.assertIsInstance(error, ValueError); self.assertEqual((compiler, bundle), (0, 0))
            self.assertEqual(list(p.name for p in dest.iterdir()), ['other-owner'])
            self.assertEqual((dest / 'other-owner').read_bytes(), b'KEEP')

    def test_archive_member_filters_and_safe_internal_link(self):
        for variant in ['external-symlink', 'external-hardlink', 'fifo', 'internal-symlink', 'internal-hardlink', 'setuid']:
            with self.case(29, variant), self.project() as (root, dest):
                def download(url, path, digest): self.synthetic_archive('sdk' if '/binaries/' in url else 'core', path, variant)
                error, compiler, bundle = self.call_main(dest, download)
                if variant in ['internal-hardlink', 'setuid']:
                    self.assertIsNone(error); self.assertEqual((compiler, bundle), (1, 1))
                    for name in installer.TOOLS: self.assertFalse((dest / 'bin' / name).stat().st_mode & 0o6000)
                else:
                    self.assertIsNotNone(error); self.assertEqual((compiler, bundle), (0, 0))
                self.assertFalse((root / 'outside').exists()); self.assertEqual((root / 'sentinel').read_bytes(), b'KEEP')

    def test_post_extraction_failure_is_explicit_and_non_overwriting(self):
        for variant in ['missing', 'wrong-version', 'workspace-exists', 'bundle-failure']:
            with self.case(30, variant), self.project() as (root, dest):
                def download(url, path, digest): self.synthetic_archive('sdk' if '/binaries/' in url else 'core', path, variant)
                error, compiler, bundle = self.call_main(dest, download,
                    version='wrong' if variant == 'wrong-version' else 'v0.10.18+6c83a7f62 (synthetic)',
                    bundle_error=subprocess.CalledProcessError(9, ['synthetic-bundle']) if variant == 'bundle-failure' else None)
                self.assertIsNotNone(error); self.assertTrue(dest.exists())
                self.assertEqual(bundle, 1 if variant == 'bundle-failure' else 0)
                self.assertEqual(compiler, 0 if variant == 'missing' else 1)
                with self.assertRaises(ValueError): installer.destination(dest)
                if variant == 'workspace-exists': self.assertEqual((dest / 'lib/core/moon.work').read_bytes(), b'x')
                self.assertEqual((root / 'sentinel').read_bytes(), b'KEEP')


if __name__ == '__main__':
    result = unittest.main(exit=False).result
    print(json.dumps({'source_sha256': hashlib.sha256((SOURCE / 'scripts/install-ci-sdk.py').read_bytes()).hexdigest(),
                      'optimized': not __debug__, 'cases': RECEIPTS}, indent=2))
    sys.exit(not result.wasSuccessful())
