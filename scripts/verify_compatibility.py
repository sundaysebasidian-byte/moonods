#!/usr/bin/env python3
"""Independent ODF date/length regression; no native app or UI activation."""
import argparse, hashlib, json, zipfile
from pathlib import Path
from lxml import etree
from fetch_schemas import SCHEMAS
from verify_external import check_package, cell_value

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', type=Path, default=Path('examples/compatibility/generated/compatibility.ods'))
    ap.add_argument('--report', type=Path, required=True)
    args = ap.parse_args()
    paths = {k: Path('.schemas') / (k + '.rng') for k in SCHEMAS}
    for k, p in paths.items():
        assert hashlib.sha256(p.read_bytes()).hexdigest() == SCHEMAS[k][1]
    schemas = {k: etree.RelaxNG(etree.parse(str(p))) for k, p in paths.items()}
    tables = check_package(args.input, schemas)
    assert list(tables) == ['日期策略', '毫米属性']
    g = tables['日期策略']
    expected = [(1, 0, ('date', '0001-01-01')), (1, 1, ('string', '0001-01-01')),
                (2, 0, ('date', '1900-01-01')), (3, 0, ('date', '9999-12-31')),
                (4, 0, ('date', '1900-01-01')), (5, 0, ('date', '1899-12-31')),
                (5, 1, ('string', '1899-12-31'))]
    for row, col, value in expected:
        assert cell_value(g[row][col]) == value
    for row in [1, 2, 3, 4, 5]:
        assert g[row][0].getAttribute('stylename') == 'DateISO'
    assert g[4][0].getAttribute('formula') == 'of:=DATE(1900;1;1)'
    ns = {'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
          'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'}
    with zipfile.ZipFile(args.input) as z:
        xml = etree.fromstring(z.read('content.xml'))
    widths = {s.get('{'+ns['style']+'}name'): s[0].get('{'+ns['style']+'}column-width')
              for s in xml.xpath('//style:style[@style:family="table-column"]', namespaces=ns)}
    columns = xml.xpath('//table:table[@table:name="毫米属性"]/table:table-column', namespaces=ns)
    actual = [widths[c.get('{'+ns['table']+'}style-name')] for c in columns]
    assert actual == ['1mm', '32mm', '500mm']
    # Negative controls validate datatypes independently of the writer.
    invalid_date = etree.fromstring(etree.tostring(xml))
    invalid_date.xpath('//table:table-cell[@office:date-value="0001-01-01"]',
                      namespaces={**ns, 'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'})[0].set(
                          '{urn:oasis:names:tc:opendocument:xmlns:office:1.0}date-value', '0000-01-01')
    assert not schemas['document'].validate(invalid_date)
    invalid_width = etree.fromstring(etree.tostring(xml))
    invalid_width.xpath('//style:table-column-properties', namespaces=ns)[0].set(
        '{'+ns['style']+'}column-width', '-1mm')
    assert not schemas['document'].validate(invalid_width)
    report = {'status': 'PASS', 'input': str(args.input),
              'sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'typed_cell_assertions': len(expected), 'official_rng_xml': 3,
              'column_mm_mapping': actual, 'negative_date_year_zero': 'REJECTED',
              'negative_width': 'REJECTED',
              'native_office': 'NOT RUN; no UI activation; this proves ODF serialization, not application rendering'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))

if __name__ == '__main__': main()
