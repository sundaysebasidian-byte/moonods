#!/usr/bin/env python3
"""Real public CSV/record consumer, Python CSV/ODS oracle, optional native Office."""
import argparse
import csv
import datetime
import hashlib
import json
import os
import subprocess
from pathlib import Path
from prepare_reader_fixtures import semantics

ROOT = Path(__file__).resolve().parents[1]


def semantic(path):
    result = {}
    fields = ['value-type', 'value', 'boolean-value', 'date-value', 'formula',
              'number-columns-spanned', 'number-rows-spanned', 'covered']
    for sheet, cells in semantics(path)['sheets'].items():
        result[sheet] = {}
        for key, cell in cells.items():
            item = {k: cell[k] for k in fields if k in cell}
            if cell.get('value-type') == 'string':
                item['text'] = cell['text']
            if item.get('value-type') == 'float':
                item['value'] = float(item['value'])
            result[sheet][key] = item
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--soffice', help='Existing native executable; no installation')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    steps = []
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'steps': steps, 'office': 'NOT_RUN', 'remote_CI': 'NOT_RUN'}
    env = dict(os.environ, ODS_VALUE_INPUT=str(out / 'input.csv'), ODS_VALUE_OUTPUT=str(out))

    def run(name, command, extra=None):
        p = subprocess.run(command, cwd=ROOT, env={**env, **(extra or {})},
                           capture_output=True, text=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(p.stdout)
        (out / (name + '.stderr.txt')).write_text(p.stderr)
        steps.append({'name': name, 'command': command, 'exit_code': p.returncode})
        if p.returncode:
            raise RuntimeError(name + ' failed; see raw logs')
        return p.stdout

    try:
        source_rows = [['Name', 'Note', 'Empty'], ['中文', 'comma,quote"and\nline', ''],
                       ['=1+2', '  spaces  ', '']]
        with (out / 'input.csv').open('w', newline='') as stream:
            csv.writer(stream, lineterminator='\r\n').writerows(source_rows)
        command = ['moon', 'run', '--target', 'js', '-j', '1', 'examples/table_csv']
        stdout = run('public-consumer', command)
        if 'VALUE_PUBLIC_CSV_RECORDS_ODS_ROUNDTRIP_OK' not in stdout:
            raise RuntimeError('missing real public consumer marker')
        with (out / 'export.csv').open(newline='') as stream:
            if list(csv.reader(stream, strict=True)) != source_rows:
                raise RuntimeError('Python CSV oracle differs from input fields')
        original = semantic(out / 'value.ods')
        for row, values in enumerate(source_rows):
            for col, text in enumerate(values):
                if original['CSV'][f'{row},{col}'] != {'value-type': 'string', 'text': text}:
                    raise RuntimeError('ODS typed CSV field differs from independent input')
        expected = {'1,1': {'value-type': 'float', 'value': 7.5},
                    '1,2': {'value-type': 'date', 'date-value': '2024-02-29'},
                    '1,3': {'value-type': 'boolean', 'boolean-value': 'true'},
                    '1,5': {'value-type': 'string', 'text': ''}}
        if any(original['Typed'].get(k) != v for k, v in expected.items()) or '1,4' in original['Typed']:
            raise RuntimeError('ODS independent typed/empty oracle failed')
        report.update(python_csv_oracle='PASS', independent_ods_oracle='PASS',
                      source_sha256={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                     for p in sorted(ROOT.glob('*.mbt'))},
                      input_sha256=hashlib.sha256((out / 'input.csv').read_bytes()).hexdigest(),
                      output_sha256=hashlib.sha256((out / 'value.ods').read_bytes()).hexdigest(),
                      scope='CSV text import/export, typed header records, two-sheet ODS write/read; no formula recalculation or format preservation')
        if args.soffice:
            version = run('office-version', [args.soffice, '--version']).strip()
            destination = out / 'office'
            destination.mkdir()
            profile = out / 'office-profile'
            report['office'] = {'status': 'STARTED', 'version': version,
                                'scope': 'real headless native ODS open/save, not GUI',
                                'executable': str(Path(args.soffice).resolve()),
                                'executable_sha256': hashlib.sha256(Path(args.soffice).resolve().read_bytes()).hexdigest()}
            run('office-resave', [args.soffice, '-env:UserInstallation=' + profile.as_uri(),
                                 '--headless', '--nologo', '--nodefault', '--norestore',
                                 '--convert-to', 'ods:calc8', '--outdir', str(destination), str(out / 'value.ods')])
            saved = destination / 'value.ods'
            if not saved.is_file():
                raise RuntimeError('Office returned without the converted ODS file')
            observed = semantic(saved)
            (out / 'office-semantics.json').write_text(json.dumps(observed, ensure_ascii=False, indent=2) + '\n')
            if observed != original:
                report['office']['semantic_comparison'] = 'FAIL'
                raise RuntimeError('Office changed typed data; see original and office semantics')
            run('public-office-readback', command, {'ODS_VALUE_READBACK': str(saved)})
            report['office'].update(status='PASS', independent_semantic_comparison='PASS',
                                    public_library_readback='PASS',
                                    output_sha256=hashlib.sha256(saved.read_bytes()).hexdigest())
        report['status'] = 'PASS'
        (out / 'original-semantics.json').write_text(json.dumps(original, ensure_ascii=False, indent=2) + '\n')
    except Exception as error:
        report.update(status='FAIL', error=str(error))
        if 'original' in locals():
            (out / 'original-semantics.json').write_text(json.dumps(original, ensure_ascii=False, indent=2) + '\n')
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'value.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
