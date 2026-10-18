#!/usr/bin/env python3
"""Build and run examples/ods_tool on the external sample and the hostile controls.

Fails closed on exit codes and on expected output markers. Not an Office-application test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXTERNAL = 'tests/reader-fixtures/external/libreoffice-dev-types.ods'
LOSS_REFUSAL = 'ERROR: data-only import requires allow_formatting_loss=true'
# control -> expected substring of the accepted-loss rejection ('' means accepted with diagnostics)
CONTROLS = {
    'deep-xml': 'XML depth/node budget exceeded',
    'dtd-entity': 'unsupported XML name',
    'duplicate-content': 'duplicate ZIP entry',
    'forged-inflate-size': 'forged ZIP uncompressed size',
    'formula-without-cache': 'formula requires a typed nonempty cache',
    'inflate-ratio': 'XML text/attribute exceeds limit',
    'invalid-date': 'invalid Gregorian day',
    'nonfinite-number': 'invalid ODF numeric lexical form',
    'repeat-overflow': 'repeat/span exceeds budget',
    'typed-prefix-alias': '',
    'unknown-currency': 'unsupported attribute',
    'wrong-table-namespace': 'unsupported spreadsheet feature',
}

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon', default=os.environ.get('MOON_BIN') or shutil.which('moon'))
    parser.add_argument('--output', type=Path, required=True, help='New directory')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env['RUST_LOG'] = 'error'
    runs = []

    def run(name, argv, extra_env=None, timeout=120):
        e = dict(env, **(extra_env or {}))
        r = subprocess.run([str(x) for x in argv], cwd=ROOT, env=e, capture_output=True, text=True, timeout=timeout)
        (out / (name + '.stdout.txt')).write_text(r.stdout, encoding='utf-8')
        (out / (name + '.stderr.txt')).write_text(r.stderr, encoding='utf-8')
        runs.append({'name': name, 'argv': [str(x) for x in argv], 'env': extra_env or {}, 'exit_code': r.returncode})
        return r

    build = run('build', [args.moon, 'build', '--target', 'js', '-j', '1', '--deny-warn', 'examples/ods_tool'])
    require(build.returncode == 0, 'ods_tool build failed')
    js = ROOT / '_build/js/debug/build/examples/ods_tool/ods_tool.js'
    require(js.exists(), 'ods_tool JS artifact missing')
    tool = lambda name, extra_env: run(name, ['node', js], extra_env)

    missing = tool('no-input', {})
    require(missing.returncode == 1 and 'set ODS_INPUT' in missing.stdout + missing.stderr, 'missing ODS_INPUT must fail with a message')
    refused = tool('external-default', {'ODS_INPUT': EXTERNAL})
    require(refused.returncode == 1 and LOSS_REFUSAL in refused.stdout + refused.stderr, 'default import must refuse data-only loss')
    edited = out / 'edited.ods'
    csv = out / 'types.csv'
    accepted = tool('external-accept-edit', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1', 'ODS_SET': '0,1,0,8.5',
                                              'ODS_OUTPUT': str(edited), 'ODS_CSV': str(csv)})
    text = accepted.stdout
    require(accepted.returncode == 0, 'accept-loss import/edit/write failed')
    for marker in ('DATA_ONLY_IMPORT', 'DOCUMENT_FORMATTING_DROPPED', 'FORMULA_CACHE_NOT_RECALCULATED',
                   'PACKAGE_PART_DROPPED', 'edited sheet[0] (1,0) = number:8.5', 're-read OK, sheets=2'):
        require(marker in text, 'missing expected output marker: ' + marker)
    require(edited.exists() and edited.stat().st_size > 0, 'edited .ods not written')
    require('\n7.5,7.5,两,' in csv.read_text(encoding='utf-8'), 'CSV unexpected content')
    bad_cell = tool('external-bad-sheet', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1', 'ODS_SET': '9,9,9,1'})
    require(bad_cell.returncode == 1 and 'no such sheet 9' in bad_cell.stdout + bad_cell.stderr, 'edit of a missing sheet must fail')

    controls = {}
    for name, expected in CONTROLS.items():
        path = 'tests/reader-fixtures/controls/%s.ods' % name
        strict = tool('control-%s-strict' % name, {'ODS_INPUT': path})
        require(strict.returncode == 1 and LOSS_REFUSAL in strict.stdout + strict.stderr, name + ': strict mode must refuse')
        loose = tool('control-%s-accept-loss' % name, {'ODS_INPUT': path, 'ODS_ACCEPT_LOSS': '1'})
        output = loose.stdout + loose.stderr
        if expected:
            require(loose.returncode == 1 and expected in output, '%s: expected rejection containing %r' % (name, expected))
            controls[name] = 'rejected'
        else:
            require(loose.returncode == 0 and 'diagnostics:' in output, name + ': expected acceptance with diagnostics')
            controls[name] = 'accepted_with_diagnostics'

    report = {
        'status': 'PASS',
        'scope': 'examples/ods_tool (JS, Node) on one external LibreOfficeDev sample and 12 synthetic controls; not an Office-application test',
        'external_sample_sha256': hashlib.sha256((ROOT / EXTERNAL).read_bytes()).hexdigest(),
        'edited_ods_sha256': hashlib.sha256(edited.read_bytes()).hexdigest(),
        'controls': controls,
        'runs': runs,
    }
    (out / 'ods-tool.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('status', 'scope', 'controls')}, ensure_ascii=False, indent=2))
    return 0

if __name__ == '__main__':
    sys.exit(main())
