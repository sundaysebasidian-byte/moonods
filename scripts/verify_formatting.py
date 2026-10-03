#!/usr/bin/env python3
"""Inspect fixed fixtures' styles with odfpy, including Calc's inherited styles.

This checks saved ODF properties, not pixels, typography or physical printing.
The bounded inspector is test-only; MoonODS has no spreadsheet reading API.
"""
import argparse, datetime, hashlib, json, re
from decimal import Decimal
from pathlib import Path
from odf import teletype
from odf.namespaces import STYLENS, FONS, NUMBERNS, TABLENS
from odf.opendocument import load
from odf.style import Style, DefaultStyle
from odf.table import Table, TableColumn, TableRow

def attr(element, namespace, name):
    return element.attributes.get((namespace, name))

def children(element):
    return [x for x in element.childNodes if getattr(x, 'qname', None)]

class Formats:
    def __init__(self, document):
        self.styles = {(attr(s, STYLENS, 'family'), attr(s, STYLENS, 'name')): s
                       for s in document.getElementsByType(Style)}
        self.defaults = {attr(s, STYLENS, 'family'): s
                         for s in document.getElementsByType(DefaultStyle)}
        self.tables = {attr(t, TABLENS, 'name'): t
                       for t in document.spreadsheet.getElementsByType(Table)}
        self.data_styles = {}
        for root in [document.styles, document.automaticstyles]:
            for s in children(root):
                if s.qname[0] == NUMBERNS:
                    self.data_styles[attr(s, STYLENS, 'name')] = s

    def effective(self, family, name):
        result = {}; chain = []
        while name:
            if name in chain or len(chain) >= 128:
                raise ValueError('Cyclic or excessive fixture style inheritance')
            style = self.styles.get((family, name))
            if style is None:
                # Calc's native saves refer to its implicit "Default" while
                # emitting style:default-style rather than a named Style.
                # Accept only this observed sentinel with a matching default;
                # other missing references remain errors.
                if name == 'Default' and family in self.defaults: break
                raise ValueError('Missing referenced fixture style: ' + name)
            chain.append(name)
            name = attr(style, STYLENS, 'parent-style-name')
        nodes = [self.defaults[family]] if family in self.defaults else []
        nodes += [self.styles[(family, n)] for n in reversed(chain)]
        for s in nodes:
            if attr(s, STYLENS, 'data-style-name'):
                result[('data-style', STYLENS, 'name')] = attr(s, STYLENS, 'data-style-name')
            for p in children(s):
                for (namespace, key), value in p.attributes.items():
                    result[(p.qname[1], namespace, key)] = value
        return result

    def column(self, sheet, col):
        if not 0 <= col < 128:
            raise ValueError('Column outside fixed fixture bounds')
        start = 0
        for c in self.tables[sheet].getElementsByType(TableColumn):
            repeat = int(attr(c, TABLENS, 'number-columns-repeated') or 1)
            if repeat < 1: raise ValueError('Invalid column repetition')
            if start <= col < start + repeat: return c
            start += repeat
        raise ValueError('Missing fixture column')

    def cell(self, sheet, address):
        match = re.fullmatch(r'([A-Z]+)([1-9][0-9]*)', address)
        if not match: raise ValueError('Invalid fixture address')
        col = 0
        for ch in match[1]: col = col * 26 + ord(ch) - 64
        col -= 1; row_number = int(match[2]) - 1
        if not 0 <= row_number < 1024: raise ValueError('Row outside fixed fixture bounds')
        column = self.column(sheet, col)
        start = 0
        for row in self.tables[sheet].getElementsByType(TableRow):
            repeat = int(attr(row, TABLENS, 'number-rows-repeated') or 1)
            if repeat < 1: raise ValueError('Invalid row repetition')
            if start <= row_number < start + repeat:
                cstart = 0
                for cell in children(row):
                    if cell.qname not in [(TABLENS, 'table-cell'), (TABLENS, 'covered-table-cell')]: continue
                    crepeat = int(attr(cell, TABLENS, 'number-columns-repeated') or 1)
                    if crepeat < 1: raise ValueError('Invalid cell repetition')
                    if cstart <= col < cstart + crepeat:
                        names = [attr(cell, TABLENS, 'style-name'), attr(row, TABLENS, 'default-cell-style-name'),
                                 attr(column, TABLENS, 'default-cell-style-name')]
                        name = next((n for n in names if n), None)
                        origin = ['cell', 'row', 'column'][names.index(name)] if name else 'default'
                        return self.effective('table-cell', name), cell, origin
                    cstart += crepeat
                raise ValueError('Missing fixture cell')
            start += repeat
        raise ValueError('Missing fixture row')

    def data_pattern(self, properties):
        name = properties.get(('data-style', STYLENS, 'name'))
        if not name: return None
        style = self.data_styles.get(name)
        if style is None: raise ValueError('Missing fixture data style: ' + name)
        return [(x.qname[1], {k[1]: v for k, v in x.attributes.items() if k[0] == NUMBERNS},
                 teletype.extractText(x)) for x in children(style)]

    def width(self, sheet, col):
        column = self.column(sheet, col)
        properties = self.effective('table-column', attr(column, TABLENS, 'style-name'))
        raw = properties.get(('table-column-properties', STYLENS, 'column-width'))
        match = re.fullmatch(r'([0-9]+(?:\.[0-9]+)?)(mm|cm|in|pt|pc)', raw or '')
        if not match: raise ValueError('Missing or unsupported fixed column length: ' + str(raw))
        factors = {'mm': Decimal(1), 'cm': Decimal(10), 'in': Decimal('25.4'),
                   'pt': Decimal('25.4') / 72, 'pc': Decimal('25.4') / 6}
        return raw, Decimal(match[1]) * factors[match[2]]

def verify_saved_formats(directory, _formats_override=None):
    result = {'scope': 'odfpy inspection of saved ODF properties; no GUI/physical-layout claim',
              'width_tolerance_mm': '0.02', 'assertions': [], 'files_sha256': {}}
    formats = {}
    for book in ['sales', 'experiment', 'formulas', 'compatibility', 'business', 'laboratory', 'declarations']:
        path = directory / (book + '.ods')
        result['files_sha256'][book] = hashlib.sha256(path.read_bytes()).hexdigest()
        formats[book] = Formats(load(str(path)))
    if _formats_override: formats.update(_formats_override)
    def check(label, expected, observed, ok=None, **details):
        result['assertions'].append({'check': label, 'expected': expected, 'observed': observed,
                                    'status': 'PASS' if (expected == observed if ok is None else ok) else 'FAIL', **details})
    for book, sheet, address in [('sales','销售报表','A1'), ('sales','销售报表','A2'), ('business','业务汇总','A1')]:
        properties, _, origin = formats[book].cell(sheet, address)
        for group, ns, key, expected in [
            ('text-properties', FONS, 'font-weight', 'bold'),
            ('text-properties', STYLENS, 'font-weight-asian', 'bold'),
            ('text-properties', STYLENS, 'font-weight-complex', 'bold'),
            ('text-properties', FONS, 'color', '#ffffff'),
            ('table-cell-properties', FONS, 'background-color', '#17324d'),
            ('table-cell-properties', FONS, 'wrap-option', 'wrap')]:
            observed = properties.get((group, ns, key))
            if observed and 'color' in key: observed = observed.lower()
            check(f'{book}/{sheet}/{address}/{key}', expected, observed, style_origin=origin)
    for book, sheet, address, key, expected in [
        ('sales','销售报表','B5','background-color','#fff2cc'),
        ('sales','销售报表','B5','wrap-option','wrap'),
        ('experiment','样本','D2','wrap-option','wrap')]:
        properties, _, origin = formats[book].cell(sheet, address)
        observed = properties.get(('table-cell-properties', FONS, key))
        check(f'{book}/{sheet}/{address}/{key}', expected, observed.lower() if observed else observed, style_origin=origin)
    for book, sheet, address in [('sales','销售报表','D3'), ('experiment','样本','B2'), ('formulas','公式缓存','A3')]:
        properties, _, origin = formats[book].cell(sheet, address)
        pattern = formats[book].data_pattern(properties)
        numbers = [p for p in pattern or [] if p[0] == 'number']
        observed = [(p[1].get('decimal-places'), p[1].get('min-integer-digits')) for p in numbers]
        check(f'{book}/{sheet}/{address}/two-decimals', [('2','1')], observed, style_origin=origin)
        check(f'{book}/{sheet}/{address}/alignment', 'end', properties.get(('paragraph-properties', FONS, 'text-align')))
    iso = [('year', {'style':'long'}, ''), ('text', {}, '-'), ('month', {'style':'long'}, ''),
           ('text', {}, '-'), ('day', {'style':'long'}, '')]
    for book, sheet, address in [('sales','销售报表','A3'), ('formulas','公式缓存','B3'),
                                  ('declarations','调用方缓存','B4'), ('compatibility','日期策略','A3')]:
        properties, cell, origin = formats[book].cell(sheet, address)
        check(f'{book}/{sheet}/{address}/iso-date-pattern', iso, formats[book].data_pattern(properties), style_origin=origin)
    # Display text is observed from Calc output, while typed-value checks are
    # separate: Decimal2 must not round the stored -0.125 to -0.13.
    _, cell, _ = formats['experiment'].cell('样本','B2')
    check('experiment/样本/B2/Calc-display-text', '-0.13', teletype.extractText(cell))
    for book, sheet, columns in [
        ('sales','销售报表',[(0,32),(1,64),(2,24),(3,34)]),
        ('experiment','样本',[(0,32),(1,30),(2,20),(3,80)]),
        ('experiment','元数据',[(1,100)]),
        ('compatibility','日期策略',[(0,32),(1,48)]),
        ('compatibility','毫米属性',[(0,1),(1,32),(2,500)]),
        ('business','业务汇总',[(0,65),(1,20),(2,35)]),
        ('laboratory','测量',[(3,100)])]:
        for col, expected in columns:
            raw, mm = formats[book].width(sheet, col)
            error = abs(mm - Decimal(expected))
            check(f'{book}/{sheet}/column-{col}/stored-width-mm', str(expected), str(mm),
                  ok=error <= Decimal('0.02'), serialized_length=raw, error_mm=str(error))
    result['passed'] = sum(a['status'] == 'PASS' for a in result['assertions'])
    result['failed'] = sum(a['status'] == 'FAIL' for a in result['assertions'])
    result['status'] = 'PASS' if result['failed'] == 0 else 'FAIL'
    return result

def formatting_controls(directory):
    """Challenge the inspector with in-memory mutations of actual saved ODF.

    These are verifier controls, not documents rejected by LibreOffice.
    Each fresh odfpy document goes through the same 50 expectations.
    """
    checks = []
    def mutate(name, book, edit):
        doc = load(str(directory / (book + '.ods'))); formats = Formats(doc)
        edit(formats)
        try:
            report = verify_saved_formats(directory, {book: formats})
            rejected = report['status'] == 'FAIL'; reason = [a['check'] for a in report['assertions'] if a['status'] == 'FAIL']
        except ValueError as e:
            rejected = True; reason = [str(e)]
        checks.append({'name':name, 'status':'PASS' if rejected else 'FAIL', 'rejection_evidence':reason})
    def property_node(formats, name, family, local):
        return next(p for p in children(formats.styles[(family,name)]) if p.qname == (STYLENS,local))
    mutate('Asian header weight changed to normal', 'sales',
           lambda f: property_node(f,'Header','table-cell','text-properties').setAttrNS(STYLENS,'font-weight-asian','normal'))
    mutate('Column width changed by 1mm', 'sales',
           lambda f: property_node(f,attr(f.column('销售报表',0),TABLENS,'style-name'),'table-column','table-column-properties').setAttrNS(STYLENS,'column-width','33mm'))
    def decimal_mutation(f):
        name = f.effective('table-cell','Decimal2')[('data-style',STYLENS,'name')]
        next(p for p in children(f.data_styles[name]) if p.qname==(NUMBERNS,'number')).setAttrNS(NUMBERNS,'decimal-places','3')
    mutate('Number format changed to three decimals','sales',decimal_mutation)
    def date_mutation(f):
        properties,_,_=f.cell('日期策略','A3'); name=properties[('data-style',STYLENS,'name')]
        next(p for p in children(f.data_styles[name]) if p.qname==(NUMBERNS,'year')).setAttrNS(NUMBERNS,'style','short')
    mutate('Date format changed to short year','compatibility',date_mutation)
    mutate('Inherited column date style replaced with Plain','compatibility',
           lambda f: f.column('日期策略',0).setAttrNS(TABLENS,'default-cell-style-name','Plain'))
    mutate('Cyclic Header inheritance','sales',
           lambda f: f.styles[('table-cell','Header')].setAttrNS(STYLENS,'parent-style-name','Header'))
    mutate('Missing non-default parent style','sales',
           lambda f: f.styles[('table-cell','Header')].setAttrNS(STYLENS,'parent-style-name','AbsentStyle'))
    return {'status':'PASS' if all(c['status']=='PASS' for c in checks) else 'FAIL',
            'scope':'In-memory verifier negative controls; no application invocation or malformed-file import claim',
            'controls':checks}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True, type=Path)
    p.add_argument('--report', required=True, type=Path)
    args = p.parse_args()
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'verifier_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'application_invoked_by_this_script': False}
    try: report.update(verify_saved_formats(args.input.resolve()))
    except Exception as e: report.update(status='FAIL', error=repr(e))
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status','passed','failed','error'] if k in report}))
    return 0 if report['status'] == 'PASS' else 1

if __name__ == '__main__': raise SystemExit(main())
