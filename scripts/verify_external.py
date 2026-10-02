#!/usr/bin/env python3
"""Independent reader and OASIS schema checks. Never import the MoonODS writer."""
import argparse, hashlib, json, struct, zipfile, tempfile
from pathlib import Path
from importlib.metadata import version
from lxml import etree
from odf.opendocument import load
from odf.table import Table
from odf import teletype
from fetch_schemas import SCHEMAS

MIME = b'application/vnd.oasis.opendocument.spreadsheet'
PATHS = ['mimetype', 'content.xml', 'styles.xml', 'META-INF/manifest.xml']
MANIFEST = 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0'
NS_TABLE = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'

def check_package(p, schemas):
    raw = p.read_bytes()
    assert raw[:4] == b'PK\x03\x04'
    with zipfile.ZipFile(p) as z:
        assert z.namelist() == PATHS, 'fixed package path set/order'
        assert z.testzip() is None, 'independent CRC verification'
        assert z.comment == b''
        assert z.read('mimetype') == MIME
        next_offset = 0
        for i in z.infolist():
            assert i.header_offset == next_offset, 'local entries contiguous and ordered'
            assert i.compress_type == zipfile.ZIP_STORED
            assert i.date_time == (1980, 1, 1, 0, 0, 0)
            assert not i.extra and not i.comment
            assert i.flag_bits == 0
            header = struct.unpack_from('<IHHHHHIIIHH', raw, i.header_offset)
            expected_header = (0x04034b50, 20, 0, 0, 0, 33, i.CRC,
                               i.compress_size, i.file_size, len(i.filename), 0)
            assert header == expected_header, 'local header disagrees with fixed profile or central directory'
            name_start = i.header_offset + 30
            assert raw[name_start:name_start+header[-2]].decode('ascii') == i.filename
            assert i.filename[0] != '/' and '\\' not in i.filename and '..' not in i.filename.split('/')
            next_offset = name_start + header[-2] + i.compress_size
        central_start = next_offset
        for i in z.infolist():
            header = struct.unpack_from('<IHHHHHHIIIHHHHHII', raw, next_offset)
            assert header == (0x02014b50, 20, 20, 0, 0, 0, 33, i.CRC,
                              i.compress_size, i.file_size, len(i.filename),
                              0, 0, 0, 0, 0, i.header_offset), 'central header fixed profile'
            name_start = next_offset + 46
            assert raw[name_start:name_start + len(i.filename)].decode('ascii') == i.filename
            next_offset = name_start + len(i.filename)
        central_size = next_offset - central_start
        end = struct.unpack_from('<IHHHHIIH', raw, next_offset)
        assert end == (0x06054b50, 0, 0, len(PATHS), len(PATHS), central_size, central_start, 0)
        assert len(raw) == next_offset + 22, 'no trailing bytes in deterministic writer profile'
        assert z.infolist()[0].header_offset == 0
        assert raw[30:38] == b'mimetype' and raw[38:38+len(MIME)] == MIME
        for name in PATHS[1:]:
            root = etree.fromstring(z.read(name))
            schema = schemas['manifest' if name.startswith('META-INF') else 'document']
            assert schema.validate(root), f'{name}: {schema.error_log}'
        root = etree.fromstring(z.read('META-INF/manifest.xml'))
        entries = root.findall(f'{{{MANIFEST}}}file-entry')
        attrs = lambda e, a: e.attrib[f'{{{MANIFEST}}}{a}']
        assert [attrs(e, 'full-path') for e in entries] == ['/', 'content.xml', 'styles.xml']
        assert attrs(entries[0], 'media-type').encode() == MIME
        assert len(entries) == len({attrs(e, 'full-path') for e in entries})
    doc = load(str(p))
    tables = doc.spreadsheet.getElementsByType(Table)
    result = {}
    for t in tables:
        rows = []
        for r in t.childNodes:
            if getattr(r, 'qname', None) != (NS_TABLE, 'table-row'): continue
            rows.append([c for c in r.childNodes if getattr(c, 'qname', None) in [(NS_TABLE, 'table-cell'), (NS_TABLE, 'covered-table-cell')]])
        result[t.getAttribute('name')] = rows
    return result

def cell_value(c):
    kind = c.getAttribute('valuetype')
    if kind is None: return None
    if kind == 'string': return ('string', c.getAttribute('stringvalue'))
    if kind == 'float': return ('number', float(c.getAttribute('value')))
    if kind == 'boolean': return ('boolean', c.getAttribute('booleanvalue') == 'true')
    if kind == 'date': return ('date', c.getAttribute('datevalue'))
    raise AssertionError(kind)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--schemas', type=Path, default=Path('.schemas'))
    ap.add_argument('--input', type=Path, default=Path('examples/generated'))
    ap.add_argument('--report', type=Path, default=Path('evidence/external.json'))
    args = ap.parse_args()
    sources = {k: args.schemas / f'{k}.rng' for k in ['document', 'manifest']}
    for key, source in sources.items():
        assert hashlib.sha256(source.read_bytes()).hexdigest() == SCHEMAS[key][1], 'official schema bytes changed'
    schemas = {k: etree.RelaxNG(etree.parse(str(v))) for k, v in sources.items()}
    # Negative control proves real strict schema validation is active.
    invalid = etree.fromstring(b'<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2"/>')
    assert not schemas['manifest'].validate(invalid)
    invalid_content = etree.fromstring(b'<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" office:version="1.3"><office:body><office:spreadsheet><bogus/></office:spreadsheet></office:body></office:document-content>')
    assert not schemas['document'].validate(invalid_content)
    reports = []
    count = 0
    def expect(c, expected):
        nonlocal count
        assert cell_value(c) == expected, (cell_value(c), expected)
        count += 1
    for name in ['sales', 'experiment', 'formulas', 'edge']:
        p = args.input / f'{name}.ods'
        tables = check_package(p, schemas)
        if name == 'sales':
            assert list(tables) == ['销售报表']
            g = tables['销售报表']
            expect(g[0][0], ('string', '2026年10月销售（合成示例）'))
            assert g[0][0].getAttribute('numbercolumnsspanned') == '4'
            assert all(c.qname[1] == 'covered-table-cell' for c in g[0][1:])
            for col, text in enumerate(['月份', '产品', '销量', '金额']): expect(g[1][col], ('string', text))
            expect(g[2][0], ('date', '2026-10-01'))
            expect(g[2][1], ('string', '月光笔 <限定>&"版"'))
            expect(g[2][2], ('number', 12.0)); expect(g[2][3], ('number', 359.88))
            expect(g[3][1], ('string', '便签')); expect(g[3][2], ('number', 8.0)); expect(g[3][3], ('number', 40.0))
            expect(g[4][2], ('number', 20.0)); expect(g[4][3], ('number', 399.88))
            assert g[1][0].getAttribute('stylename') == 'Header'
            with zipfile.ZipFile(p) as z:
                content = etree.fromstring(z.read('content.xml'))
                styles = etree.fromstring(z.read('styles.xml'))
            n = {'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0', 'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0', 'number': 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0'}
            width = '{'+n['style']+'}column-width'
            assert [x.attrib[width] for x in content.xpath('//style:table-column-properties', namespaces=n)] == ['24mm', '32mm', '34mm', '64mm']
            assert styles.xpath('//style:style[@style:name="Header"]/style:table-cell-properties/@fo:background-color', namespaces=n) == ['#17324D']
            assert styles.xpath('//number:number-style[@style:name="N2"]/number:number/@number:decimal-places', namespaces=n) == ['2']
        elif name == 'experiment':
            assert list(tables) == ['样本', '元数据']
            g = tables['样本']
            expect(g[1][0], ('date', '2024-02-29')); expect(g[1][1], ('number', -0.125)); expect(g[1][2], ('boolean', True))
            text = ' 中文  双空格\t制表\n下一行 😀 '
            expect(g[1][3], ('string', text)); assert teletype.extractText(g[1][3]) == text
            expect(g[2][0], None); expect(g[2][1], ('number', 0.0)); expect(g[2][2], ('boolean', False)); expect(g[2][3], ('string', ''))
            expect(tables['元数据'][0][1], ('string', '合成测试数据，无个人信息'))
            expect(tables['元数据'][1][1], ('string', '长文与XML<&>转义。' * 1000))
        elif name == 'formulas':
            g = tables['公式缓存']
            for r, c, f, v in [
                (2, 0, 'of:=SUM([.A1:.A2])', ('number', 30.0)),
                (0, 1, 'of:=[.A1]<[.A2]', ('boolean', True)),
                (1, 1, 'of:="中文 & 结果"', ('string', '中文 & 结果')),
                (2, 1, 'of:=DATE(2026;10;1)', ('date', '2026-10-01'))]:
                assert g[r][c].getAttribute('formula') == f
                expect(g[r][c], v)
        else:
            assert list(tables) == ['边界 & XML', '空表']
            g = tables['边界 & XML']
            text = ' <&>"\'\t\n\r 😀 中文 '
            for r, v in enumerate([('string', text), ('string', ''), None, ('number', 1e300), ('number', 1e-300), ('boolean', False), ('date', '0001-01-01'), ('date', '9999-12-31'), ('string', 'x' * 32767)]): expect(g[r][0], v)
            assert teletype.extractText(g[0][0]) == text
            expect(tables['空表'][0][0], None)
        reports.append({'file': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'bytes': p.stat().st_size,
                        'tables': list(tables), 'official_rng': 'PASS (content, styles, manifest)', 'zip_crc_paths_headers': 'PASS', 'odfpy_values': 'PASS'})
    # Corrupt otherwise valid files independently of the writer, and verify our
    # checker rejects wrong paths/order/MIME/CRC. No self-generated parser.
    controls = []
    with tempfile.TemporaryDirectory() as d:
        reference = args.input / 'sales.ods'
        with zipfile.ZipFile(reference) as z:
            entries = [(name, z.read(name)) for name in z.namelist()]
        for mode in ['path', 'order', 'mimetype', 'crc']:
            p = Path(d) / (mode + '.ods')
            altered = entries.copy()
            if mode == 'path': altered[-1] = ('../manifest.xml', altered[-1][1])
            if mode == 'order': altered[0], altered[1] = altered[1], altered[0]
            if mode == 'mimetype': altered[0] = ('mimetype', b'application/octet-stream')
            with zipfile.ZipFile(p, 'w', compression=zipfile.ZIP_STORED) as z:
                for name, data in altered:
                    i = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                    z.writestr(i, data)
            if mode == 'crc':
                raw = bytearray(p.read_bytes()); raw[38] ^= 1; p.write_bytes(raw)
            try:
                check_package(p, schemas)
            except (AssertionError, zipfile.BadZipFile):
                controls.append(mode)
            else:
                raise AssertionError(f'negative package control accepted: {mode}')
        # Mutate our actual writer bytes so a different ZIP producer's metadata
        # cannot cause rejection before the intended fault is reached.
        original = reference.read_bytes()
        with zipfile.ZipFile(reference) as z:
            central = z.infolist()[-1].header_offset + 30 + len(PATHS[-1]) + z.infolist()[-1].compress_size
        mutations = [
            ('local-crc', 14, '<I'), ('local-size', 22, '<I'),
            ('local-flags', 6, '<H'), ('local-version', 4, '<H'),
            ('local-time', 10, '<H'), ('local-date', 12, '<H'),
            ('central-crc', central + 16, '<I'),
            ('central-attributes', central + 38, '<I'),
            ('end-count', len(original) - 12, '<H'),
            ('end-central-size', len(original) - 10, '<I'),
        ]
        for mode, offset, fmt in mutations:
            raw = bytearray(original)
            struct.pack_into(fmt, raw, offset, struct.unpack_from(fmt, raw, offset)[0] ^ 1)
            p = Path(d) / (mode + '.ods'); p.write_bytes(raw)
            try: check_package(p, schemas)
            except (AssertionError, zipfile.BadZipFile, struct.error): controls.append(mode)
            else: raise AssertionError(f'negative header control accepted: {mode}')
        p = Path(d) / 'trailing-bytes.ods'; p.write_bytes(original + b'ignored tail')
        try: check_package(p, schemas)
        except (AssertionError, zipfile.BadZipFile): controls.append('trailing-bytes')
        else: raise AssertionError('negative trailing-byte control accepted')
    report = {'status': 'PASS', 'versions': {x: version(x) for x in ['odfpy', 'lxml', 'defusedxml']},
              'schema_sha256': {k: hashlib.sha256(v.read_bytes()).hexdigest() for k,v in sources.items()},
              'zip_profile_scope': 'Exact deterministic MoonODS profile; stricter than general ODF ZIP requirements',
              'negative_schema_control': 'PASS (document and manifest)', 'negative_package_controls': controls, 'typed_cell_assertions': count, 'files': reports,
              'libreoffice': 'NOT RUN BY THIS SCRIPT; separate application evidence required'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__': main()
