#!/usr/bin/env python3
"""Exercise actual CLI formula-text policy; only synthetic private files are used."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    records = []
    with tempfile.TemporaryDirectory(prefix='moonods-cli-options-') as tmp:
        root = Path(tmp)
        source, csv, ods = [root / n for n in ['input.ods', 'out.csv', 'out.ods']]
        mime = 'application/vnd.oasis.opendocument.spreadsheet'
        content = ('<o:document-content xmlns:o="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
                   'xmlns:t="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
                   'xmlns:x="urn:oasis:names:tc:opendocument:xmlns:text:1.0" o:version="1.3">'
                   '<o:body><o:spreadsheet><t:table t:name="Policy"><t:table-column/>'
                   '<t:table-row><t:table-cell o:value-type="string"><x:p>=1+2</x:p>'
                   '</t:table-cell></t:table-row></t:table></o:spreadsheet></o:body></o:document-content>')
        manifest = ('<m:manifest xmlns:m="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" m:version="1.3">'
                    '<m:file-entry m:full-path="/" m:media-type="' + mime + '"/>'
                    '<m:file-entry m:full-path="content.xml" m:media-type="text/xml"/></m:manifest>')
        with zipfile.ZipFile(source, 'w') as archive:
            for name, data in [('mimetype', mime), ('content.xml', content), ('META-INF/manifest.xml', manifest)]:
                archive.writestr(name, data)
        original = source.read_bytes()
        for token in ['', '0', '1', '2', 'true', 'false', ' 1', '1 ', '\t1']:
            csv.write_bytes(b'OLD CSV'); ods.write_bytes(b'OLD ODS')
            env = {k: v for k, v in os.environ.items() if not k.startswith('ODS_')}
            env.update(ODS_INPUT=str(source), ODS_CSV=str(csv), ODS_OUTPUT=str(ods),
                       ODS_ACCEPT_LOSS='1', ODS_CSV_REJECT_FORMULA_TEXT=token)
            result = subprocess.run(['node', str(CLI)], env=env, text=True, capture_output=True, timeout=15)
            accept = token in ('', '0')
            require(result.returncode == (0 if accept else 1), 'unexpected result for ' + repr(token))
            require(source.read_bytes() == original, 'input changed')
            if accept:
                require(csv.read_bytes() == b'"=1+2"\r\n', 'default text preservation changed')
                with zipfile.ZipFile(ods) as archive:
                    require(archive.testzip() is None, 'output CRC')
            else:
                require(csv.read_bytes() == b'OLD CSV' and ods.read_bytes() == b'OLD ODS', 'refusal changed output')
                require(('formula-like text' if token == '1' else 'must be 0 or 1') in result.stdout,
                        'missing policy-specific diagnostic')
            require(not list(root.glob('.moonods-*.tmp')), 'temporary file leak')
            records.append({'token': token, 'accepted': accept, 'exit_code': result.returncode, 'status': 'PASS'})
    print(json.dumps({'status': 'PASS', 'cli_sha256': hashlib.sha256(CLI.read_bytes()).hexdigest(), 'cases': records}))


if __name__ == '__main__':
    main()
