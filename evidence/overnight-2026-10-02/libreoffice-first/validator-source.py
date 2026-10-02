#!/usr/bin/env python3
"""Real, explicitly selected installed LibreOffice engine imports our fixtures.

This is headless application verification, not a GUI or physical-layout test.
No installation, publication, macros, server listener or persistent profile.
"""
import argparse, datetime, hashlib, json, math, subprocess, tempfile, zipfile
from pathlib import Path
from lxml import etree
from fetch_schemas import SCHEMAS
from verify_external import check_package

ROOT = Path(__file__).resolve().parent.parent
NS = {'x': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
RID = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def read_xlsx(path):
    """Inspect real LibreOffice output, independently of the MoonODS writer."""
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            for s in etree.fromstring(z.read('xl/sharedStrings.xml')):
                strings.append(''.join(s.xpath('.//x:t/text()', namespaces=NS)))
        book = etree.fromstring(z.read('xl/workbook.xml'))
        rels = {r.get('Id'): r.get('Target') for r in etree.fromstring(z.read('xl/_rels/workbook.xml.rels'))}
        result = {}
        for s in book.xpath('./x:sheets/x:sheet', namespaces=NS):
            target = rels[s.get(RID)]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            xml = etree.fromstring(z.read(target))
            cells = {}
            for c in xml.xpath('./x:sheetData/x:row/x:c', namespaces=NS):
                kind = c.get('t'); value = c.find('x:v', NS)
                text = value.text if value is not None else None
                if kind == 's': v = strings[int(text)]
                elif kind == 'inlineStr': v = ''.join(c.xpath('.//x:t/text()', namespaces=NS))
                elif kind == 'b': v = text == '1'
                elif kind in ('str', 'e', 'd'): v = text
                else: v = float(text) if text is not None else None
                formula = c.find('x:f', NS)
                cells[c.get('r')] = {'value': v, 'type': kind, 'style': c.get('s'),
                                    'formula': formula.text if formula is not None else None}
            result[s.get('name')] = {'cells': cells,
                'merges': xml.xpath('./x:mergeCells/x:mergeCell/@ref', namespaces=NS),
                'columns': [dict(c.attrib) for c in xml.xpath('./x:cols/x:col', namespaces=NS)]}
        return result

def serial(iso):
    day = datetime.date.fromisoformat(iso)
    count = (day - datetime.date(1899, 12, 30)).days
    return count - 1 if day < datetime.date(1900, 3, 1) else count

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--soffice', required=True, type=Path)
    ap.add_argument('--reuse-input', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'scope': 'Installed LibreOffice headless Calc imports fixed no-macro ODS and exports XLSX; independently read cached values',
              'not_tested': ['GUI appearance', 'print layout', 'absolute physical millimeter widths',
                             'stable LibreOffice release versions', 'all ODF date ranges', 'arbitrary formulas'],
              'steps': [], 'assertions': []}
    def run(name, command):
        r = subprocess.run([str(s) for s in command], cwd=ROOT, capture_output=True, text=True, timeout=120)
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
            work = Path(temp); profile = work / 'profile'; exports = work / 'xlsx'; exports.mkdir()
            run('calc-import-export', [args.soffice, '-env:UserInstallation=' + profile.as_uri(),
                '--headless', '--nologo', '--nodefault', '--norestore',
                '--convert-to', 'xlsx:Calc MS Excel 2007 XML', '--outdir', exports, *inputs])
            books = {}
            for p in inputs:
                output = exports / (p.stem + '.xlsx')
                assert output.is_file() and output.stat().st_size > 0, 'Missing real Calc output: ' + p.stem
                books[p.stem] = read_xlsx(output)
                (out / output.name).write_bytes(output.read_bytes())
        assert before == {str(p): digest(p) for p in inputs}, 'Application modified input ODS'
        report['inputs_unchanged_sha256'] = before
        def expect(book, sheet, address, value):
            observed = books[book][sheet]['cells'][address]['value']
            assert type(observed) == type(value) and observed == value, (book, sheet, address, observed, value)
            report['assertions'].append({'book': book, 'sheet': sheet, 'cell': address, 'status': 'PASS'})
        for address, value in [('A1','2026年10月销售（合成示例）'), ('B3','月光笔 <限定>&"版"'),
                               ('C5',20.0), ('D5',399.88), ('A3',float(serial('2026-10-01')))]:
            expect('sales','销售报表',address,value)
        assert books['sales']['销售报表']['merges'] == ['A1:D1']
        for address, value in [('A2',float(serial('2024-02-29'))), ('B2',-0.125), ('C2',True),
                               ('D2',' 中文  双空格\t制表\n下一行 😀 '), ('B3',0.0), ('C3',False)]:
            expect('experiment','样本',address,value)
        expect('experiment','元数据','B2','长文与XML<&>转义。' * 1000)
        for address,value in [('A3',30.0),('B1',True),('B2','中文 & 结果'),('B3',float(serial('2026-10-01')))]:
            expect('formulas','公式缓存',address,value)
        for address,value in [('A1',' <&>"\'\t\n\r 😀 中文 '),('A4',1e300),('A5',1e-300),('A6',False),('A9','x'*32767)]:
            expect('edge','边界 & XML',address,value)
        for address,value in [('A3','教学套件 <A>&B'),('B5',7.0),('C5',62.5)]:
            expect('business','业务汇总',address,value)
        assert books['business']['业务汇总']['merges'] == ['A1:C1']
        for address,value in [('A2',float(serial('2024-02-29'))),('B2',-2.5),('C2',True),
                               ('D2',' 中文  空白\t制表\n下一行 😀 '),('C3',False)]:
            expect('laboratory','测量',address,value)
        for address,value in [('B1',3.0),('B2',True),('B3','下游中文 & 缓存'),('B4',float(serial('2026-10-01')))]:
            expect('declarations','调用方缓存',address,value)
        report['formula_cache_observation'] = {'input_odf_cache':99, 'calc_output_cache':3,
            'interpretation':'LibreOffice Calc recalculated SUM(1,2); MoonODS preserves caller cache and does not evaluate'}
        report['date_and_width_observations'] = books['compatibility']
        report['headless_value_checks'] = 'PASS'
        report['status'] = 'PARTIAL'
        report['interpretation'] = 'All listed headless import/value checks pass; GUI, physical layout and other versions remain unverified'
    except Exception as e:
        report['status'] = 'FAIL'; report['error'] = repr(e)
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'libreoffice.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:report[k] for k in ['status','application_version','headless_value_checks','error'] if k in report}, ensure_ascii=False))
    return 0 if report.get('headless_value_checks') == 'PASS' else 1

if __name__ == '__main__': raise SystemExit(main())
