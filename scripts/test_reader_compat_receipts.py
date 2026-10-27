"""Failure receipts must belong to the command that actually failed."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import verify_reader_compat as compat


class ReceiptTests(unittest.TestCase):
    def check_failure(self, mode):
        with tempfile.TemporaryDirectory(prefix='moonods-receipt-control-') as tmp:
            root = Path(tmp)
            source = root/'tests/reader-fixtures/source/rich-text.fods'
            source.parent.mkdir(parents=True)
            source.write_bytes((compat.ROOT/'tests/reader-fixtures/source/rich-text.fods').read_bytes())
            artifact = root/'_build/js/debug/build/examples/ods_tool/ods_tool.js'
            artifact.parent.mkdir(parents=True)
            artifact.write_text('// no execution in this injected failure control')
            out = root/'receipt'
            def fake_run(command, **kwargs):
                if command[0] == 'node' and command[1].endswith('ods_tool.js'):
                    if mode == 'timeout':
                        raise subprocess.TimeoutExpired(command, 120)
                    if mode == 'spawn':
                        raise FileNotFoundError('controlled unavailable executable')
                    return subprocess.CompletedProcess(command, 1, 'ERROR: controlled refusal', '')
                return subprocess.CompletedProcess(command, 0, 'controlled version/build', '')
            expected = {'timeout': subprocess.TimeoutExpired,
                        'spawn': FileNotFoundError,
                        'exit': RuntimeError}[mode]
            with patch.object(compat, 'ROOT', root), patch.object(compat.subprocess, 'run', side_effect=fake_run), patch.object(sys, 'argv', ['verify_reader_compat.py', '--soffice', '/controlled/soffice', '--output', str(out)]):
                with self.assertRaises(expected):
                    compat.main()
            receipt = json.loads((out/'receipt.json').read_text())
            self.assertEqual(receipt['status'], 'FAIL')
            steps = receipt['steps']
            self.assertEqual(steps[-1]['name'], 'direct-rich-import')
            self.assertTrue(steps[-1]['input']['unchanged'])
            self.assertEqual(steps[-1]['input']['sha256_before'], steps[-1]['input']['sha256_after'])
            self.assertFalse(any('input' in step for step in steps[:-1]))
            self.assertEqual(steps[-1]['exit_code'], 1 if mode == 'exit' else None)
            if mode != 'exit':
                self.assertIn('execution_error', steps[-1])

    def test_timeout(self):
        self.check_failure('timeout')

    def test_spawn_failure(self):
        self.check_failure('spawn')

    def test_nonzero_exit(self):
        self.check_failure('exit')


if __name__ == '__main__':
    unittest.main()
