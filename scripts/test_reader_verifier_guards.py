#!/usr/bin/env python3
"""Negative controls for verification only; mocked tools are NOT core/office evidence.
Run both normally and with python -O. Each case executes the verifier's main.
"""
import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import verify_reader_review as review
import verify_typed_reader as typed

ROOT = Path(__file__).resolve().parents[1]

class Guards(unittest.TestCase):
    def review_case(self, kind, message):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'source'
            shutil.copytree(ROOT,root,ignore=shutil.ignore_patterns('.git','.mooncakes','_build','evidence','__pycache__'))
            source = root/'reader_zip_wbtest.mbt'
            manifest = json.loads((root/'tests/reader-fixtures/controls-manifest.json').read_text())
            name = next(iter(manifest))
            if kind == 'hash':
                (root/'tests/reader-fixtures/controls'/name).write_bytes(b'corrupt')
            elif kind == 'missing':
                source.write_text(source.read_text().replace('"'+name+'"', '"missing.ods"'))
            elif kind == 'embedded':
                import re
                source.write_text(re.sub(r'("'+re.escape(name)+r'"\s*=>\s*\[\s*)\d+',r'\g<1>0',source.read_text(),count=1))
            elif kind == 'producer':
                (root/'tests/reader-fixtures/external/libreoffice-dev-types.ods').write_bytes(b'corrupt')
            fake = subprocess.CompletedProcess([],0,stdout='mock tool',stderr='')
            with patch.object(review,'ROOT',root), patch.object(review.subprocess,'run',return_value=fake), patch.object(sys,'argv',['verify']), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit): review.main()
            report = json.loads((root/'evidence/typed-reader-20261015/review-validation.json').read_text())
            self.assertEqual(report['result'],'FAIL')
            self.assertIn(message,report['error'])

    def test_fixture_hash(self): self.review_case('hash','fixture hash mismatch')
    def test_missing_embedded_fixture(self): self.review_case('missing','missing embedded fixture')
    def test_embedded_bytes(self): self.review_case('embedded','embedded byte mismatch')
    def test_producer_bytes(self): self.review_case('producer','external producer embedded byte mismatch')

    def typed_case(self, kind, message):
        before={'sheets':{'Types':{'1,0':{'value-type':'float','value':'7.5','text':'7.5'}}}}
        edited=copy.deepcopy(before); edited['sheets']['Types']['1,0'].update(value='8.5',text='8.5')
        observations=[before, before if kind=='edit' else edited]
        if kind=='resave': observations.append(before)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'source'
            shutil.copytree(ROOT,root,ignore=shutil.ignore_patterns('.git','.mooncakes','_build','evidence','__pycache__'))
            def fake_run(args, **kwargs):
                if args[0]=='moon':
                    Path(kwargs['env']['ODS_OUTPUT']).write_bytes(b'mocked output')
                elif '--convert-to' in args and kind!='missing':
                    dest=Path(args[args.index('--outdir')+1]); (dest/'edited-libreoffice.ods').write_bytes(b'mocked save')
                return subprocess.CompletedProcess(args,1 if kind=='exit' and '--convert-to' in args else 0,stdout='MockOffice',stderr='')
            argv=['verify'] + ([] if kind=='edit' else ['--soffice','mock-office'])
            with patch.object(typed,'ROOT',root), patch.object(typed.subprocess,'run',side_effect=fake_run), patch.object(typed,'semantics',side_effect=observations), patch.object(sys,'argv',argv), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError,message): typed.main()
            self.assertFalse((root/'evidence/typed-reader-20261015/public-consumer.json').exists())

    def test_missed_edit(self): self.typed_case('edit','missed the requested edit')
    def test_office_failed_exit(self): self.typed_case('exit','LibreOffice save failed')
    def test_office_missing_output(self): self.typed_case('missing','LibreOffice save failed')
    def test_office_changed_data(self): self.typed_case('resave','application changed typed data')

if __name__=='__main__': unittest.main()
