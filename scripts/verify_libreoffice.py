#!/usr/bin/env python3
"""Real, explicitly selected installed LibreOffice engine imports our fixtures.

This is headless application verification, not a GUI or physical-layout test.
No installation, publication, macros, server listener or persistent profile.
"""
import argparse, datetime, hashlib, json, os, subprocess, tempfile, zipfile
from pathlib import Path
from lxml import etree
from fetch_schemas import SCHEMAS
from verify_external import check_package
from odf.opendocument import load
from odf.table import Table, TableRow
from odf import teletype
from verify_formatting import verify_saved_formats, formatting_controls

ROOT = Path(__file__).resolve().parent.parent

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def read_application_ods(path):
    """Read Calc's native save with odfpy, expanding only typed fixture cells."""
    doc = load(str(path)); result = {}
    for table in doc.spreadsheet.getElementsByType(Table):
        cells = {}; row_index = 0; merges = []
        for row in table.getElementsByType(TableRow):
            repeat_rows = int(row.getAttribute('numberrowsrepeated') or 1)
            col = 0
            for cell in row.childNodes:
                if getattr(cell, 'qname', (None, None))[1] not in ['table-cell', 'covered-table-cell']: continue
                repeat_cols = int(cell.getAttribute('numbercolumnsrepeated') or 1)
                oa = lambda name: cell.attributes.get(('urn:oasis:names:tc:opendocument:xmlns:office:1.0', name))
                ta = lambda name: cell.attributes.get(('urn:oasis:names:tc:opendocument:xmlns:table:1.0', name))
                kind = oa('value-type')
                value = None
                if kind == 'string':
                    value = oa('string-value')
                    if value is None: value = teletype.extractText(cell)
                elif kind == 'float': value = float(oa('value'))
                elif kind == 'boolean': value = oa('boolean-value') == 'true'
                elif kind == 'date': value = oa('date-value')
                if kind:
                    assert row_index + repeat_rows <= 1024 and col + repeat_cols <= 128, 'Fixture expansion limit'
                    for r in range(row_index, row_index + repeat_rows):
                        for c in range(col, col + repeat_cols):
                            n = c + 1; letters = ''
                            while n: n, digit = divmod(n - 1, 26); letters = chr(65 + digit) + letters
                            cells[letters + str(r+1)] = {'value': value, 'type': kind,
                                'formula': ta('formula'), 'style': ta('style-name')}
                if ta('number-columns-spanned'):
                    merges.append({'row':row_index, 'col':col, 'rows':int(ta('number-rows-spanned') or 1),
                                   'cols':int(ta('number-columns-spanned'))})
                col += repeat_cols
            row_index += repeat_rows
        result[table.getAttribute('name')] = {'cells':cells, 'merges':merges}
    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--soffice', required=True, type=Path)
    ap.add_argument('--reuse-input', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--fontconfig', type=Path, help='Optional existing task-local fontconfig; no installation')
    args = ap.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'verifier_sha256': digest(Path(__file__)),
              'scope': 'Installed LibreOffice headless Calc imports fixed no-macro ODS and saves native ODS; odfpy independently reads saved typed values',
              'not_tested': ['GUI appearance', 'print layout', 'absolute physical millimeter widths',
                             'stable LibreOffice release versions', 'all ODF date ranges', 'arbitrary formulas'],
              'steps': [], 'assertions': []}
    def run(name, command):
        env = os.environ.copy()
        if args.fontconfig:
            env['FONTCONFIG_FILE'] = str(args.fontconfig.resolve())
            env['FONTCONFIG_PATH'] = str(args.fontconfig.resolve().parent)
        r = subprocess.run([str(s) for s in command], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(r.stdout)
        (out / (name + '.stderr.txt')).write_text(r.stderr)
        report['steps'].append({'name': name, 'command': [str(s) for s in command], 'exit_code': r.returncode})
        assert r.returncode == 0, f'{name} failed; retained stdout/stderr'
        return r.stdout.strip()
    try:
        assert args.soffice.is_file(), 'Existing explicitly supplied LibreOffice required; no installation'
        report['application_version'] = run('version', [args.soffice, '--version'])
        inputs = [ROOT / 'examples/generated' / (n + '.ods') for n in ['sales', 'experiment', 'formulas', 'edge']]
        inputs += [ROOT / 'examples/compatibility/generated/compatibility.ods']
        inputs += [args.reuse_input.resolve() / (n + '.ods') for n in ['business', 'laboratory', 'declarations']]
        source_schemas = {k: ROOT / '.schemas' / (k + '.rng') for k in SCHEMAS}
        assert all(digest(p) == SCHEMAS[k][1] for k, p in source_schemas.items())
        schemas = {k: etree.RelaxNG(etree.parse(str(p))) for k, p in source_schemas.items()}
        before = {str(p): digest(p) for p in inputs}
        for p in inputs: check_package(p, schemas)
        with tempfile.TemporaryDirectory(prefix='moonods-lo-') as temp:
            work = Path(temp); profile = work / 'profile'; exports = work / 'ods'; exports.mkdir()
            run('calc-import-export', [args.soffice, '-env:UserInstallation=' + profile.as_uri(),
                '--headless', '--nologo', '--nodefault', '--norestore',
                '--convert-to', 'ods:calc8', '--outdir', exports, *inputs])
            books = {}
            for p in inputs:
                output = exports / (p.stem + '.ods')
                assert output.is_file() and output.stat().st_size > 0, 'Missing real Calc output: ' + p.stem
                books[p.stem] = read_application_ods(output)
                (out / output.name).write_bytes(output.read_bytes())
        assert before == {str(p): digest(p) for p in inputs}, 'Application modified input ODS'
        report['inputs_unchanged_sha256'] = before
        report['imported_files'] = len(inputs)
        report['source_rng_xml_count'] = 3 * len(inputs)
        report['roundtrip_output_schema_claim'] = 'Not validated against ODF1.3 RNG; application may save its own ODF version/profile'
        def expect(book, sheet, address, value, kind=None):
            expected_kind = kind or ('boolean' if type(value) == bool else 'float' if type(value) == float else 'string')
            observed = books[book][sheet]['cells'].get(address, {'value':None, 'type':None})
            ok = observed['type'] == expected_kind and type(observed['value']) == type(value) and observed['value'] == value
            item = {'book': book, 'sheet': sheet, 'cell': address, 'status': 'PASS' if ok else 'FAIL'}
            if not ok: item.update(expected={'value':value, 'type':expected_kind}, observed=observed)
            report['assertions'].append(item)
        for address, value in [('A1','2026年10月销售（合成示例）'), ('B3','月光笔 <限定>&"版"'),
                               ('C5',20.0), ('D5',399.88)]:
            expect('sales','销售报表',address,value)
        expect('sales','销售报表','A3','2026-10-01','date')
        assert books['sales']['销售报表']['merges'] == [{'row':0,'col':0,'rows':1,'cols':4}]
        for address, value in [('B2',-0.125), ('C2',True),
                               ('D2',' 中文  双空格\t制表\n下一行 😀 '), ('B3',0.0), ('C3',False)]:
            expect('experiment','样本',address,value)
        expect('experiment','样本','A2','2024-02-29','date')
        expect('experiment','元数据','B2','长文与XML<&>转义。' * 1000)
        for address,value in [('A3',30.0),('B1',True),('B2','中文 & 结果')]:
            expect('formulas','公式缓存',address,value)
        expect('formulas','公式缓存','B3','2026-10-01','date')
        for address,value in [('A1',' <&>"\'\t\n\r 😀 中文 '),('A4',1e300),('A5',1e-300),('A6',False),('A9','x'*32767)]:
            expect('edge','边界 & XML',address,value)
        for address,value in [('A3','教学套件 <A>&B'),('B5',7.0),('C5',62.5)]:
            expect('business','业务汇总',address,value)
        assert books['business']['业务汇总']['merges'] == [{'row':0,'col':0,'rows':1,'cols':3}]
        report['merge_assertions'] = 2
        for address,value in [('B2',-2.5),('C2',True),
                               ('D2',' 中文  空白\t制表\n下一行 😀 '),('C3',False)]:
            expect('laboratory','测量',address,value)
        expect('laboratory','测量','A2','2024-02-29','date')
        for address,value in [('B1',99.0),('B2',True),('B3','下游中文 & 缓存')]:
            expect('declarations','调用方缓存',address,value)
        expect('declarations','调用方缓存','B4','2026-10-01','date')
        report['formula_cache_observation'] = {'input_odf_cache':99, 'calc_native_save_cache':books['declarations']['调用方缓存']['cells']['B1']['value'],
            'interpretation':'Native ODS save can keep a supplied cache; prior XLSX export recalculated to 3. Reader save/export behavior is not a MoonODS calculation engine.'}
        report['date_and_width_observations'] = books['compatibility']
        report['saved_formatting'] = verify_saved_formats(out)
        report['formatting_negative_controls'] = formatting_controls(out)
        report['passed'] = sum(a['status'] == 'PASS' for a in report['assertions'])
        report['failed'] = sum(a['status'] == 'FAIL' for a in report['assertions'])
        report['headless_value_checks'] = 'PASS' if report['failed'] == 0 else 'PARTIAL'
        report['headless_formatting_checks'] = report['saved_formatting']['status']
        report['status'] = 'PARTIAL' if (report['headless_value_checks'] == 'PASS' and
            report['headless_formatting_checks'] == 'PASS' and
            report['formatting_negative_controls']['status'] == 'PASS') else 'FAIL'
        report['interpretation'] = 'Listed headless checks retain every failure; GUI, physical layout and other versions remain unverified'
    except Exception as e:
        report['status'] = 'FAIL'; report['error'] = repr(e)
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'libreoffice.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:report[k] for k in ['status','application_version','headless_value_checks','headless_formatting_checks','passed','failed','error'] if k in report}, ensure_ascii=False))
    return 0 if (report.get('headless_value_checks') == 'PASS' and
                 report.get('headless_formatting_checks') == 'PASS' and
                 report.get('formatting_negative_controls', {}).get('status') == 'PASS') else 1

if __name__ == '__main__': raise SystemExit(main())
