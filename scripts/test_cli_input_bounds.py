"""Execute exact embedded Node adapters, without substituting compiled CLI tests."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def embedded_adapter(path, name):
    source = path.read_text()
    match = re.search(r'extern "js" fn ' + name + r'\([^=]+?=\n((?:  #\|[^\n]*\n)+)', source)
    if not match:
        raise ValueError('missing JS adapter: ' + name)
    return '\n'.join(line.removeprefix('  #| ') for line in match[1].splitlines())


class CliInputBounds(unittest.TestCase):
    def adapters(self):
        return [('ods_tool', embedded_adapter(ROOT / 'examples/ods_tool/main.mbt', 'read_file'), 33554432),
                ('reconcile', embedded_adapter(ROOT / 'examples/reconcile/main.mbt', 'read_bytes'), 16)]

    def execute(self, adapter, path, limit):
        program = 'const read = ' + adapter + ';\ntry { const b=read(process.argv[1],Number(process.argv[2])); console.log(b.length); } catch(e) { console.error(e.message); process.exitCode=1; }'
        return subprocess.run(['node', '-e', program, str(path), str(limit)], capture_output=True,
                              text=True, timeout=4)

    def test_oversize_rejected_before_read(self):
        for name, adapter, limit in self.adapters():
            with self.subTest(adapter=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'large'
                with path.open('wb') as stream:
                    stream.truncate(limit + 1)
                result = self.execute(adapter, path, limit)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn('budget', result.stderr)

    def test_fifo_rejected_without_waiting_for_writer(self):
        for name, adapter, limit in self.adapters():
            with self.subTest(adapter=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'pipe'
                os.mkfifo(path)
                result = self.execute(adapter, path, limit)
                self.assertEqual(result.returncode, 1)
                self.assertIn('regular file', result.stderr)

    def test_small_regular_file(self):
        for name, adapter, limit in self.adapters():
            with self.subTest(adapter=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'input'
                path.write_bytes(b'1234')
                result = self.execute(adapter, path, limit)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), '4')

    def test_regular_stat_then_fifo_open_does_not_block(self):
        for name, adapter, limit in self.adapters():
            with self.subTest(adapter=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'replaced-with-fifo'
                os.mkfifo(path)
                # Simulate a path becoming a FIFO after the initial stat. The
                # actual open must be nonblocking and fstat must reject it.
                program = ("const fs=require('node:fs');"
                           "fs.statSync=()=>({isFile:()=>true,size:0});const read="
                           + adapter
                           + ';try{read(process.argv[1],Number(process.argv[2]));process.exitCode=2}'
                             'catch(e){console.error(e.message);process.exitCode=1}')
                result = subprocess.run(['node', '-e', program, str(path), str(limit)],
                                        capture_output=True, text=True, timeout=4)
                self.assertEqual(result.returncode, 1)
                self.assertIn('regular file', result.stderr)

    def test_size_growth_before_open_is_rejected_before_read(self):
        for name, adapter, limit in self.adapters():
            with self.subTest(adapter=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'grown-file'
                with path.open('wb') as stream:
                    stream.truncate(limit + 1)
                program = ("const fs=require('node:fs');"
                           "fs.statSync=()=>({isFile:()=>true,size:0});"
                           "fs.readSync=()=>{throw new Error('unexpected read')};const read="
                           + adapter
                           + ';try{read(process.argv[1],Number(process.argv[2]));process.exitCode=2}'
                             'catch(e){console.error(e.message);process.exitCode=1}')
                result = subprocess.run(['node', '-e', program, str(path), str(limit)],
                                        capture_output=True, text=True, timeout=4)
                self.assertEqual(result.returncode, 1)
                self.assertIn('budget', result.stderr)
                self.assertNotIn('unexpected read', result.stderr)


if __name__ == '__main__':
    unittest.main()
