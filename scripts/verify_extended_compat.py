#!/usr/bin/env python3
"""Real Office/source checks for opt-in types and formatting; never installs/publishes."""
import argparse
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile
from fractions import Fraction
from decimal import Decimal
from lxml import etree as ET
from fetch_schemas import SCHEMAS
from prepare_reader_fixtures import PREFIX, SUFFIX, package, fixed_producer_xml, ordered_columns
from verify_reader_compat import typed
from ods_value_oracle import decimal_identity

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixed_widths(path):
    """Independent oracle for this produced fixture's explicit column widths."""
    style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
    table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'
    defs = {}
    with zipfile.ZipFile(path) as z:
        roots = [ET.fromstring(z.read(n), ET.XMLParser(resolve_entities=False, no_network=True, load_dtd=False)) for n in ['styles.xml', 'content.xml']]
    for root in roots:
        for node in root.findall('.//{'+style+'}style'):
            if node.get('{'+style+'}family') == 'table-column':
                defs[node.get('{'+style+'}name')] = node
    def width(name, seen=()):
        if name in seen or len(seen)>16 or name not in defs:
            return None
        node = defs[name]
        prop = node.find('{'+style+'}table-column-properties')
        raw = prop.get('{'+style+'}column-width') if prop is not None else None
        if raw is None:
            parent = node.get('{'+style+'}parent-style-name')
            return width(parent, seen+(name,)) if parent else None
        units = {'mm':Fraction(1),'cm':Fraction(10),'in':Fraction(127,5),'pt':Fraction(127,360),'pc':Fraction(127,30)}
        for suffix, scale in units.items():
            if raw.endswith(suffix):
                number = Fraction(Decimal(raw[:-len(suffix)]))*scale
                return int(number) if number.denominator==1 and 1<=number<=500 else None
        return None
    sheet=roots[1].find('.//{'+table+'}table')
    result=[]
    for node in ordered_columns(sheet):
        repeat=int(node.get('{'+table+'}number-columns-repeated','1'))
        require(1<=repeat<=128 and len(result)+repeat<=128,'width oracle column budget')
        result.extend([width(node.get('{'+table+'}style-name'))]*repeat)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--moon', default='moon')
    p.add_argument('--soffice', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'status': 'RUNNING', 'steps': [], 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'scope': 'synthetic FODS produced by actual stable LibreOffice, opt-in JS public API CLI, independent exact lexical-value oracle and official ODF schema',
              'not_tested': ['Excel', 'GUI/print', 'arbitrary styles', 'financial arithmetic', 'general timestamp/duration arithmetic']}
    def run(label, command, env=None, expected=0):
        step = {'name': label, 'command': [str(c) for c in command], 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'expected_exit_code': expected, 'exit_code': None}
        if env is not None:
            step['environment_overrides'] = {k: v for k, v in env.items() if k.startswith('ODS_')}
        report['steps'].append(step)
        try:
            r = subprocess.run(step['command'], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        except (subprocess.TimeoutExpired, OSError) as exc:
            step['execution_error'] = type(exc).__name__
            raise
        finally:
            step['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        step['exit_code'] = r.returncode
        (out/(label+'.stdout.txt')).write_text(r.stdout)
        (out/(label+'.stderr.txt')).write_text(r.stderr)
        require(r.returncode == expected, label+' unexpected exit')
        return r.stdout
    def office(label, source):
        dest = out/(label+'-saved')
        dest.mkdir()
        before = sha(source)
        with tempfile.TemporaryDirectory(prefix='moonods-extended-office-') as tmp:
            run(label, [a.soffice, '-env:UserInstallation='+Path(tmp).as_uri(), '--headless', '--nologo', '--nodefault', '--norestore', '--convert-to', 'ods:calc8', '--outdir', dest, source])
        result = dest/(source.stem+'.ods')
        require(result.is_file() and sha(source) == before, label+' missing output or mutated input')
        report['steps'][-1]['input'] = {'sha256_before': before, 'sha256_after': sha(source)}
        return result
    def cli(label, source, options=None, expected=0):
        dest, csv_path = out/(label+'.ods'), out/(label+'.csv')
        dest.write_bytes(b'PREVIOUS ODS')
        csv_path.write_bytes(b'PREVIOUS CSV')
        env = {k: v for k, v in os.environ.items() if not k.startswith('ODS_')}
        env.update(ODS_INPUT=str(source), ODS_ACCEPT_LOSS='1', ODS_EXTENDED_TYPES='1', ODS_PRESERVE_BASIC='1', ODS_OUTPUT=str(dest))
        if options:
            env.update({k: str(v) for k, v in options.items()})
        if env.get('ODS_CSV') == 'REQUEST':
            env['ODS_CSV'] = str(csv_path)
        before = sha(source)
        try:
            log = run(label, ['node', tool], env, expected)
        finally:
            report['steps'][-1]['input'] = {'path': str(source), 'sha256_before': before, 'sha256_after': sha(source), 'unchanged': sha(source) == before}
        require(sha(source) == before, label+' modified input')
        if expected:
            require(dest.read_bytes() == b'PREVIOUS ODS' and csv_path.read_bytes() == b'PREVIOUS CSV', label+' modified old outputs')
            require(not list(out.glob('.moonods-*.tmp')), label+' left staging files')
        else:
            require(dest.read_bytes() != b'PREVIOUS ODS', label+' failed to write ODS')
            validate_schema(dest)
        return dest, csv_path, log
    def validate_schema(path):
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, 'output CRC mismatch')
            for name in ['content.xml', 'styles.xml', 'META-INF/manifest.xml']:
                schema = schemas['manifest' if name.startswith('META-INF') else 'document']
                xml = ET.fromstring(archive.read(name), ET.XMLParser(resolve_entities=False, no_network=True, load_dtd=False))
                require(schema.validate(xml), name+' schema failed: '+str(schema.error_log.last_error))
        report.setdefault('schema_validated_outputs', []).append({'name': path.name, 'sha256': sha(path)})
    try:
        report['moon'] = run('versions', [a.moon, 'version', '--all'])
        report['office_version'] = run('office-version', [a.soffice, '--version']).strip()
        schemas = {}
        for key, (_, digest) in SCHEMAS.items():
            file = ROOT/'.schemas'/(key+'.rng')
            require(sha(file) == digest, 'schema provenance mismatch')
            schemas[key] = ET.RelaxNG(ET.parse(str(file)))
        require(not schemas['document'].validate(ET.fromstring(b'<bogus/>')), 'schema negative control failed')
        run('build', [a.moon, 'build', '--target', 'js', '-j', '1', '--deny-warn', 'examples/ods_tool'])
        candidates = [ROOT/'_build/js/debug/build/examples/ods_tool/ods_tool.js', ROOT/'_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js']
        tool = next((c for c in candidates if c.is_file()), None)
        require(tool is not None, 'missing built JS')
        source = ROOT/'tests/reader-fixtures/source/extended-types.fods'
        produced = office('producer', source)
        report['producer'] = {'synthetic_source': str(source.relative_to(ROOT)), 'synthetic_source_sha256': sha(source), 'actual_ods_sha256': sha(produced), 'license': 'original MIT synthetic data, generated by recorded LibreOffice; not an official corpus/customer workbook'}
        widths = fixed_widths(produced)
        require(widths[0] == 127, 'producer did not retain exact 5in width')
        report['producer_exact_integer_widths'] = widths
        original = typed(produced)
        report['original_typed'] = original
        cells = original['Extended']
        require(cells['1,0']['value-type'] == 'currency' and cells['1,0']['currency'] == 'USD', 'producer lost currency unit')
        require(cells['1,1']['value-type'] == 'percentage', 'producer lost percentage type')
        require(cells['1,2']['value-type'] == 'time' and 'time-value' in cells['1,2'], 'producer lost duration type')
        require(cells['1,3']['value-type'] == 'date' and 'T' in cells['1,3']['date-value'], 'producer lost dateTime')
        cli('legacy-refusal', produced, {'ODS_EXTENDED_TYPES': '0'}, expected=1)
        cli('csv-policy-refusal', produced, {'ODS_CSV': 'REQUEST'}, expected=1)
        first, csv_path, log = cli('typed-edit', produced, {'ODS_SET': '0,1,0,13.75', 'ODS_CSV': 'REQUEST', 'ODS_EXTENDED_CSV_TEXT': '1'})
        expected = json.loads(json.dumps(original))
        expected['Extended']['1,0']['value'] = decimal_identity('13.75')
        require(typed(first) == expected, 'typed edit changed kind/unit/temporal/other data')
        with csv_path.open(newline='', encoding='utf-8') as stream:
            rows = list(csv.reader(stream))
        require(rows[1][0] == 'currency:USD:13.75' and rows[1][1] == 'percentage:0.25', 'tagged CSV unit policy mismatch')
        require('BASIC_FORMATTING_SUBSET' in log and 'width sheet[0] col=0: 127mm' in log, 'missing real exact-width retention evidence')
        require(fixed_widths(first) == widths, 'output changed exact integer-mm width subset')
        again, _, _ = cli('library-reread', first)
        require(typed(again) == expected, 'library reread changed typed data')
        saved = office('office-resave', first)
        require(fixed_widths(saved) == widths, 'Office resave changed retained exact width subset')
        observed = typed(saved)
        report['office_resave_typed'] = observed
        require(observed == expected, 'Office resave changed a type/unit/amount/temporal value; inspect exact observed fields')
        final, _, _ = cli('office-reread', saved)
        require(typed(final) == expected, 'Office output library reread mismatch')
        for label, attrs, reason in [
            ('currency-precision', 'o:value-type="currency" o:value="9007199254740993" o:currency="USD"', 'currency decimal cannot roundtrip'),
            ('currency-code', 'o:value-type="currency" o:value="1" o:currency="usd"', 'currency requires'),
            ('duration-calendar', 'o:value-type="time" o:time-value="P1M"', 'duration'),
            ('timestamp-offset', 'o:value-type="date" o:date-value="2026-10-26T01:30:00+14:01"', 'offset'),
        ]:
            bad = out/(label+'-input.ods')
            bad.write_bytes(package((PREFIX+'<t:table-row><t:table-cell '+attrs+'/></t:table-row>'+SUFFIX).encode()))
            _, _, refusal = cli('reject-'+label, bad, {'ODS_CSV': 'REQUEST', 'ODS_EXTENDED_CSV_TEXT': '1'}, expected=1)
            require(reason in refusal and 'row 0 col 0' in refusal, label+' missing specific refusal')
        for option in ['ODS_EXTENDED_TYPES', 'ODS_PRESERVE_BASIC', 'ODS_EXTENDED_CSV_TEXT']:
            _, _, refusal = cli('reject-'+option.lower(), produced, {option: 'typo'}, expected=1)
            require(option+' must be 0 or 1' in refusal, 'unknown option not rejected')
        # Offset preservation is tested separately from the floating timestamps
        # used in the positive Office workflow; do not hide an app normalization.
        offset = out/'offset-input.ods'
        offset.write_bytes(package((PREFIX+'<t:table-row><t:table-cell o:value-type="date" o:date-value="2026-10-26T01:30:00.125+08:00"/></t:table-row>'+SUFFIX).encode()))
        offset_out, _, _ = cli('offset-library', offset)
        require(typed(offset_out) == typed(offset), 'library dropped offset/fraction')
        offset_saved = office('offset-office-probe', offset_out)
        report['offset_office_boundary'] = {'input': typed(offset_out), 'observed': typed(offset_saved), 'exactly_preserved': typed(offset_saved) == typed(offset_out), 'scope': 'one explicit-offset probe, no general Office timezone guarantee'}
        report['status'] = 'PASS_WITH_RECORDED_BOUNDARIES'
    except Exception as exc:
        report['status'] = 'FAIL'
        report['error'] = str(exc)
        raise
    finally:
        report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out/'receipt.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
