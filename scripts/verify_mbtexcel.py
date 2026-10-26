#!/usr/bin/env python3
"""Packaged public MoonODS + registry mbtexcel in one module, with OOXML oracle."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile
from xml.etree import ElementTree as ET
from prepare_reader_fixtures import semantics

ROOT = Path(__file__).resolve().parents[1]
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def inspect_xlsx(path):
    with zipfile.ZipFile(path) as archive:
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            for item in ET.fromstring(archive.read('xl/sharedStrings.xml')):
                strings.append(''.join(item.itertext()))
        rels = {r.attrib['Id']: r.attrib['Target'] for r in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
        sheets = {}
        for sheet in ET.fromstring(archive.read('xl/workbook.xml')).find('m:sheets', NS):
            target = rels[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
            name = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            xml = ET.fromstring(archive.read(name))
            cells = {}
            for cell in xml.findall('.//m:sheetData/m:row/m:c', NS):
                require(cell.find('m:f', NS) is None, 'cache-only export retained an unconverted formula')
                kind = cell.attrib.get('t', 'n')
                raw = cell.findtext('m:v', default='', namespaces=NS)
                if kind == 's': value = ('string', strings[int(raw)])
                elif kind == 'inlineStr': value = ('string', ''.join(cell.find('m:is', NS).itertext()))
                elif kind == 'b': value = ('boolean', raw == '1')
                elif kind == 'n' and raw: value = ('float', float(raw))
                else: raise RuntimeError('unexpected OOXML cell type: ' + kind)
                cells[cell.attrib['r']] = value
            sheets[sheet.attrib['name']] = {'cells': cells, 'merges': [m.attrib['ref'] for m in xml.findall('m:mergeCells/m:mergeCell', NS)]}
        return sheets

def cell_name(row, col):
    result = ''
    col += 1
    while col:
        col, digit = divmod(col - 1, 26)
        result = chr(65 + digit) + result
    return result + str(row + 1)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    report = {'status': 'FAIL', 'scope': 'same-module public API integration; no publication or office application run'}
    def run(label, command, cwd, env=None):
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=180)
        (out / (label + '.stdout.txt')).write_text(result.stdout)
        (out / (label + '.stderr.txt')).write_text(result.stderr)
        require(result.returncode == 0, label + ' failed; see saved logs')
        return result.stdout
    try:
        run('package', ['moon', 'package', '--frozen'], ROOT)
        archive = ROOT / '_build/publish/sundaysebasidian-byte-moonods-0.2.0.zip'
        shutil.copyfile(archive, out / 'candidate.zip')
        source = ROOT / 'tests/reader-fixtures/external/libreoffice-dev-types.ods'
        output = out / 'edited.xlsx'
        with tempfile.TemporaryDirectory(prefix='moonods-mbtexcel-') as temp:
            work = Path(temp)
            with zipfile.ZipFile(archive) as package:
                package.extractall(work / 'candidate')
            shutil.copytree(ROOT / 'fixtures/mbtexcel-consumer', work / 'consumer')
            (work / 'moon.work').write_text('members = ["candidate", "consumer"]\n')
            graph = json.loads(run('dependency-tree', ['moon', 'tree', '--json'], work / 'consumer'))
            modules = {m['name']: m for m in graph['modules']}
            require(modules['sundaysebasidian-byte/moonods']['source']['kind'] == 'local', 'candidate is not local')
            require(Path(modules['sundaysebasidian-byte/moonods']['source']['path']).resolve() == (work / 'candidate').resolve(), 'candidate path mismatch')
            require(modules['moonbitlang/mbtexcel']['version'] == '0.3.0', 'mbtexcel version mismatch')
            require(modules['moonbit-community/flate']['version'] == '0.9.0', 'shared flate version mismatch')
            run('format', ['moon', 'fmt', '--check', 'src'], work / 'consumer')
            run('check', ['moon', 'check', '--target', 'js', '-j', '1', '--deny-warn'], work / 'consumer')
            log = run('consumer', ['moon', 'run', '--target', 'js', '-j', '1', 'src'], work / 'consumer', dict(os.environ, ODS_INPUT=str(source), XLSX_OUTPUT=str(output)))
            require('FORMULA_DEFAULT_REJECTION_VERIFIED' in log and 'FORMULA_DROPPED|Types|0|6' in log, 'formula policy evidence missing')
            require('SHEET1_ORDER_AND_1900_DATE_VERIFIED' in log, 'sheet ordering or date boundary evidence missing')
        # The ODS oracle reuses one record for repeated cells; detach each cell
        # before applying a one-cell edit.
        expected = json.loads(json.dumps(semantics(source)['sheets']))
        expected['Types']['1,0']['value'] = '8.5'
        actual = inspect_xlsx(output)
        require('NUMBER_SIGNED_ZERO_CHANGED|Types|0|0' in log, 'signed zero loss was not reported')
        require(list(actual) == list(expected), 'sheet order changed')
        count = 0
        for name, cells in expected.items():
            observed = {}; merges = []
            for key, cell in cells.items():
                if cell.get('covered'): continue
                row, col = map(int, key.split(',')); address = cell_name(row, col)
                kind = cell['value-type']
                if kind == 'string': value = cell['text']
                elif kind == 'float': value = float(cell['value'])
                elif kind == 'boolean': value = cell['boolean-value'] == 'true'
                elif kind == 'date':
                    date = datetime.date.fromisoformat(cell['date-value'])
                    value = (date - datetime.date(1899, 12, 31)).days + (date >= datetime.date(1900, 3, 1))
                    kind = 'float'
                else: raise RuntimeError('oracle unsupported type: ' + kind)
                observed[address] = (kind, value); count += 1
                if 'number-columns-spanned' in cell:
                    merges.append(address + ':' + cell_name(row + int(cell['number-rows-spanned']) - 1, col + int(cell['number-columns-spanned']) - 1))
            require(actual[name]['cells'] == observed, 'independent OOXML typed values differ: ' + name)
            require(actual[name]['merges'] == merges, 'merge ranges changed: ' + name)
        report.update(status='PASS', typed_cells=count, sheets=len(expected), dependencies={'mbtexcel': '0.3.0', 'flate': '0.9.0'}, input_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(), formula_policy='default rejection; explicit cache-only export reports FORMULA_DROPPED', signed_zero='mbtexcel normalizes -0 to +0; NUMBER_SIGNED_ZERO_CHANGED verified', application_validation='NOT RUN')
    except Exception as error:
        report['error'] = str(error)
    (out / 'integration.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if report['status'] == 'PASS' else 1

if __name__ == '__main__':
    raise SystemExit(main())
