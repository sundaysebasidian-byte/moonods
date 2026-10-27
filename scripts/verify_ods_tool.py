#!/usr/bin/env python3
"""Build and run examples/ods_tool on the external sample and the hostile controls.

Fails closed on exit codes and on expected output markers. Not an Office-application test.
"""
import argparse
import csv as csv_module
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from prepare_reader_fixtures import package, PREFIX, SUFFIX

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
    if not js.exists():
        js = ROOT / '_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js'
    require(js.exists(), 'ods_tool JS artifact missing')
    tool = lambda name, extra_env: run(name, ['node', js], extra_env)

    missing = tool('no-input', {})
    require(missing.returncode == 1 and 'set ODS_INPUT' in missing.stdout + missing.stderr, 'missing ODS_INPUT must fail with a message')
    refused = tool('external-default', {'ODS_INPUT': EXTERNAL})
    require(refused.returncode == 1 and LOSS_REFUSAL in refused.stdout + refused.stderr, 'default import must refuse data-only loss')
    edited = out / 'edited.ods'
    csv = out / 'types.csv'
    accepted = tool('external-accept-edit', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1', 'ODS_SET': '0,1,0,8.5',
                                              'ODS_OUTPUT': str(edited), 'ODS_CSV': str(csv), 'ODS_CSV_CACHE': '1'})
    text = accepted.stdout
    require(accepted.returncode == 0, 'accept-loss import/edit/write failed')
    for marker in ('DATA_ONLY_IMPORT', 'DOCUMENT_FORMATTING_DROPPED', 'FORMULA_CACHE_NOT_RECALCULATED',
                   'PACKAGE_PART_DROPPED', 'CSV_FORMULA_DROPPED sheet=Types row=0 col=6', 'edited sheet[0] (1,0) = number:8.5', 're-read OK, sheets=2'):
        require(marker in text, 'missing expected output marker: ' + marker)
    require(edited.exists() and edited.stat().st_size > 0, 'edited .ods not written')
    with csv.open(encoding='utf-8', newline='') as stream:
        rows = list(csv_module.reader(stream, strict=True))
    require(rows[1][:3] == ['8.5', '7.5', '两'], 'CSV must contain edited values')
    bad_cell = tool('external-bad-sheet', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1', 'ODS_SET': '9,9,9,1'})
    require(bad_cell.returncode == 1 and 'no such sheet 9' in bad_cell.stdout + bad_cell.stderr, 'edit of a missing sheet must fail')

    # Refusals must leave existing outputs byte-for-byte intact.
    for name, extra in {
        'bad-fractional-index': {'ODS_SET': '0,1.5,0,1'},
        'bad-infinite-index': {'ODS_SET': 'Infinity,0,0,1'},
        'bad-negative-index': {'ODS_SET': '-1,0,0,1'},
        'bad-sheet-with-exports': {'ODS_SET': '9,0,0,1'},
        'formula-csv-explicit-rejection': {'ODS_CSV_CACHE': '0'},
        'invalid-csv-cache-policy': {'ODS_CSV_CACHE': 'typo'},
    }.items():
        csv.write_bytes(b'previous CSV')
        edited.write_bytes(b'previous ODS')
        failed = tool(name, {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1',
                            'ODS_CSV': str(csv), 'ODS_OUTPUT': str(edited), **extra})
        require(failed.returncode == 1, name + ': expected failure')
        require(csv.read_bytes() == b'previous CSV' and edited.read_bytes() == b'previous ODS',
                name + ': modified output on validation failure')
    csv.write_bytes(b'previous CSV')
    io_failure = tool('staging-failure', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1',
                      'ODS_CSV': str(csv), 'ODS_CSV_CACHE': '1',
                      'ODS_OUTPUT': str(out / 'missing-directory' / 'output.ods')})
    require(io_failure.returncode == 1 and csv.read_bytes() == b'previous CSV',
            'staging failure must preserve the first output')
    require(not list(out.glob('.moonods-*.tmp')), 'staging failure leaked temporary files')
    alias = tool('output-alias', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1',
                                 'ODS_OUTPUT': EXTERNAL})
    require(alias.returncode == 1 and 'must be distinct' in alias.stdout, 'input overwrite must fail')
    alias_dir = out / 'alias-directory'
    alias_dir.symlink_to(out, target_is_directory=True)
    alias_new = tool('new-output-parent-alias', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1',
                    'ODS_CSV': str(out / 'new-output'), 'ODS_OUTPUT': str(alias_dir / 'new-output')})
    require(alias_new.returncode == 1 and 'must be distinct' in alias_new.stdout and
            not (out / 'new-output').exists(), 'new output parent symlink alias must fail before writes')
    alias_dir.unlink()
    # Restore a valid demonstration after the destructive-output sentinels.
    accepted = tool('external-final-export', {'ODS_INPUT': EXTERNAL, 'ODS_ACCEPT_LOSS': '1',
                    'ODS_SET': '0,1,0,8.5', 'ODS_OUTPUT': str(edited), 'ODS_CSV': str(csv)})
    require(accepted.returncode == 0, 'final example export failed')

    literal = out / 'formula-like-text.ods'
    literal.write_bytes(package((PREFIX + '<t:table-row><t:table-cell o:value-type="string"><x:p>=1+2</x:p></t:table-cell></t:table-row>' + SUFFIX).encode()))
    policy_csv = out / 'policy.csv'
    faithful = tool('literal-default', {'ODS_INPUT': str(literal), 'ODS_ACCEPT_LOSS': '1', 'ODS_CSV': str(policy_csv)})
    require(faithful.returncode == 0 and policy_csv.read_bytes() == b'"=1+2"\r\n',
            'default CSV text semantics changed')
    protected = tool('literal-guard', {'ODS_INPUT': str(literal), 'ODS_ACCEPT_LOSS': '1',
                     'ODS_CSV': str(policy_csv), 'ODS_CSV_REJECT_FORMULA_TEXT': '1'})
    require(protected.returncode == 1 and 'CSV formula-like text at row 0 col 0' in protected.stdout and
            policy_csv.read_bytes() == b'"=1+2"\r\n', 'explicit CSV text guard must reject without changing output')

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
