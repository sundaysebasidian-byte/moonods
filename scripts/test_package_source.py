"""Source export guards in synthetic, unconnected repositories only."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile
import package_source as exporter


class SourceExportGuards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / 'project'
        self.root.mkdir()
        self.git('init', '-q')
        (self.root / 'main.mbt').write_text('reviewed source\n')
        self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.PIPE)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Synthetic Test', '-c', 'user.email=test@example.invalid',
                 'commit', '-qm', 'synthetic')

    def export(self, output):
        with mock.patch.object(exporter, 'ROOT', self.root), \
             mock.patch.object(sys, 'argv', ['export', '--output', str(output)]), \
             contextlib.redirect_stdout(io.StringIO()):
            exporter.main()

    def test_clean_exact_manifest_and_untracked_exclusion(self):
        for name in ['汉 字.mbt', 'line\nbreak.mbt', '-leading.mbt']:
            (self.root / name).write_text(name)
        self.commit()
        (self.root / 'private-untracked').write_text('not part of export')
        a, b = self.base / 'a.zip', self.base / 'b.zip'
        self.export(a); self.export(b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
        with zipfile.ZipFile(a) as z:
            state = json.loads(z.read('MoonODS/SOURCE_STATE.json'))
            self.assertNotIn('MoonODS/private-untracked', z.namelist())
            self.assertEqual(set(z.namelist()),
                             {'MoonODS/' + n for n in state['files_sha256']} | {'MoonODS/SOURCE_STATE.json'})
            for name, digest in state['files_sha256'].items():
                self.assertEqual(hashlib.sha256(z.read('MoonODS/' + name)).hexdigest(), digest)

    def test_hidden_index_changes_do_not_impersonate_head(self):
        for flag in ['assume-unchanged', 'skip-worktree']:
            with self.subTest(flag=flag):
                self.git('update-index', '--' + flag, 'main.mbt')
                (self.root / 'main.mbt').write_text('hidden changes')
                self.assertFalse(self.git('status', '--porcelain', '--untracked-files=no').strip())
                out = self.base / 'blocked.zip'
                with self.assertRaisesRegex(SystemExit, 'do not match reviewed HEAD'):
                    self.export(out)
                self.assertFalse(out.exists())
                self.git('update-index', '--no-' + flag, 'main.mbt')
                self.git('checkout', '--', 'main.mbt')

    def test_reserved_metadata_cannot_replace_tracked_bytes(self):
        path = self.root / 'SOURCE_STATE.json'
        path.write_text('user-owned contents')
        self.commit()
        out = self.base / 'blocked.zip'
        with self.assertRaisesRegex(SystemExit, 'reserved'):
            self.export(out)
        self.assertEqual(path.read_text(), 'user-owned contents')
        self.assertFalse(out.exists())

    def test_output_aliases_preserve_source(self):
        source = self.root / 'main.mbt'
        for kind in ['same', 'hardlink', 'symlink']:
            with self.subTest(kind=kind):
                out = source if kind == 'same' else self.base / kind
                if kind == 'hardlink': os.link(source, out)
                if kind == 'symlink': out.symlink_to(source)
                before = source.read_bytes()
                with self.assertRaisesRegex(SystemExit, 'alias tracked source'):
                    self.export(out)
                self.assertEqual(source.read_bytes(), before)

    def test_git_metadata_output_preserved(self):
        out = self.root / '.git/HEAD'
        before = out.read_bytes()
        with self.assertRaisesRegex(SystemExit, 'Git metadata'):
            self.export(out)
        self.assertEqual(out.read_bytes(), before)

    def test_output_hardlink_to_git_metadata_and_fifo_refused(self):
        head = self.root / '.git/HEAD'
        linked = self.base / 'head-alias.zip'
        os.link(head, linked)
        before = head.read_bytes()
        with self.assertRaisesRegex(SystemExit, 'unlinked regular file'):
            self.export(linked)
        self.assertEqual(head.read_bytes(), before)
        fifo = self.base / 'pipe.zip'
        os.mkfifo(fifo)
        with self.assertRaisesRegex(SystemExit, 'unlinked regular file'):
            self.export(fifo)

    def test_generated_tracked_source_and_dirty_source_refused(self):
        (self.root / 'payload.wasm').write_bytes(b'generated')
        self.commit()
        with self.assertRaisesRegex(SystemExit, 'generated binaries'):
            self.export(self.base / 'generated.zip')
        (self.root / 'main.mbt').write_text('uncommitted')
        with self.assertRaisesRegex(SystemExit, 'Commit reviewed source'):
            self.export(self.base / 'dirty.zip')
        self.assertFalse((self.base / 'generated.zip').exists())
        self.assertFalse((self.base / 'dirty.zip').exists())


if __name__ == '__main__':
    unittest.main()
