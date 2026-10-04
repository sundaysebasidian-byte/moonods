#!/usr/bin/env python3
"""Independent odfpy/RNG assertions for the three synthetic consumer scenarios."""
from lxml import etree
from odf import teletype
from fetch_schemas import SCHEMAS
from hashlib import sha256
from verify_external import check_package, cell_value

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

def verify_generated(generated, schema_root):
    sources = {k: schema_root / (k + '.rng') for k in SCHEMAS}
    assert all(digest(p) == SCHEMAS[k][1] for k, p in sources.items())
    schemas = {k: etree.RelaxNG(etree.parse(str(p))) for k, p in sources.items()}
    count = 0
    def expect(cell, value):
        nonlocal count
        assert cell_value(cell) == value, (cell_value(cell), value)
        count += 1
    b = check_package(generated / 'business.ods', schemas)
    assert list(b) == ['业务汇总']
    g = b['业务汇总']
    expect(g[0][0], ('string', '下游提供的商品清单'))
    assert g[0][0].getAttribute('numbercolumnsspanned') == '3'
    assert all(c.qname[1] == 'covered-table-cell' for c in g[0][1:])
    for c, v in enumerate(['商品', '数量', '金额']): expect(g[1][c], ('string', v))
    for r, values in [(2, [('string', '教学套件 <A>&B'), ('number', 2.0), ('number', 50.0)]),
                      (3, [('string', '耗材'), ('number', 5.0), ('number', 12.5)]),
                      (4, [('string', '合计'), ('number', 7.0), ('number', 62.5)])]:
        for c, value in enumerate(values): expect(g[r][c], value)
    assert g[2][2].getAttribute('stylename') == 'Decimal2'
    l = check_package(generated / 'laboratory.ods', schemas)
    assert list(l) == ['测量', '记录来源']
    note = ' 中文  空白\t制表\n下一行 😀 '
    for r, values in [(1, [('date', '2024-02-29'), ('number', -2.5), ('boolean', True), ('string', note)]),
                      (2, [('date', '2026-10-01'), ('number', 0.0), ('boolean', False), ('string', '')])]:
        for c, value in enumerate(values): expect(l['测量'][r][c], value)
    assert teletype.extractText(l['测量'][1][3]) == note
    expect(l['记录来源'][0][0], ('string', '合成批次 LAB-02'))
    expect(l['记录来源'][1][0], None); expect(l['记录来源'][1][1], ('string', ''))
    d = check_package(generated / 'declarations.ods', schemas)
    assert list(d) == ['调用方缓存']
    g = d['调用方缓存']
    expect(g[0][0], ('number', 1.0)); expect(g[1][0], ('number', 2.0))
    for r, f, value in [
        (0, 'of:=SUM([.A1:.A2])', ('number', 99.0)),
        (1, 'of:=[.A1]<[.A2]', ('boolean', True)),
        (2, 'of:="下游中文 & 缓存"', ('string', '下游中文 & 缓存')),
        (3, 'of:=DATE(2026;10;1)', ('date', '2026-10-01'))]:
        assert g[r][1].getAttribute('formula') == f
        expect(g[r][1], value)
    return {'status': 'PASS', 'typed_cell_assertions': count, 'official_rng_xml_count': 9, 'package_checks': 'PASS', 'inconsistent_cache_preserved': 99, 'calculation_performed': False}
