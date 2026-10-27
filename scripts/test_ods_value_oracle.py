import tempfile
from pathlib import Path
import unittest
from ods_value_oracle import decimal_identity, binary64_expected
from verify_reader_compat import typed
from prepare_reader_fixtures import PREFIX, SUFFIX, package


class ExactOracleTests(unittest.TestCase):
    def fixture(self, root, name, cell):
        target = root/name
        target.write_bytes(package((PREFIX+'<t:table-row>'+cell+'</t:table-row>'+SUFFIX).encode()))
        return typed(target)

    def test_mutating_zero_sign_or_large_precision_is_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def number(name, raw):
                return self.fixture(root, name, '<t:table-cell o:value-type="float" o:value="'+raw+'"/>')
            self.assertNotEqual(number('negative.ods', '-0'), number('positive.ods', '0'))
            self.assertNotEqual(number('exact.ods', '9007199254740992'), number('changed.ods', '9007199254740993'))
            self.assertEqual(number('one.ods', '1.00'), number('other.ods', '+1e0'))

    def test_attribute_only_string_is_authoritative_and_mutation_is_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = self.fixture(root, 'first.ods', '<t:table-cell o:value-type="string" o:string-value="stored"/>')
            changed = self.fixture(root, 'second.ods', '<t:table-cell o:value-type="string" o:string-value="changed"/>')
            self.assertEqual(original['Input']['0,0']['text'], 'stored')
            self.assertNotEqual(original, changed)
            display = self.fixture(root, 'display.ods', '<t:table-cell o:value-type="string" o:string-value="stored"><x:p>different display</x:p></t:table-cell>')
            self.assertEqual(display, original)

    def test_binary64_expectation_is_explicit_and_preserves_zero_sign(self):
        self.assertNotEqual(decimal_identity('9007199254740993'), binary64_expected('9007199254740993'))
        self.assertEqual(binary64_expected('9007199254740993'), decimal_identity('9007199254740992'))
        self.assertEqual(binary64_expected('-0'), '-0')
        self.assertEqual(decimal_identity('1.0000000000000000000000000000000000000001'), '+10000000000000000000000000000000000000001e-40')
        for invalid in ['NaN', 'Infinity', '1_000', '']:
            with self.assertRaises(ValueError):
                decimal_identity(invalid)
        with self.assertRaises(ValueError):
            binary64_expected('1e-999')


class StructuralAndUnitOracleTests(unittest.TestCase):
    def test_column_wrappers_preserve_default_style_width_order_and_mutations(self):
        from verify_basic_formatting import fixture, effective_cells, DEFS
        from verify_extended_compat import fixed_widths
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            defs = DEFS + '<style:style style:name="W127" style:family="table-column"><style:table-column-properties style:column-width="5in"/></style:style><style:style style:name="W40" style:family="table-column"><style:table-column-properties style:column-width="4cm"/></style:style>'
            row = '<t:table-row><t:table-cell o:value-type="string"><x:p>same</x:p></t:table-cell><t:table-cell o:value-type="string"><x:p>same</x:p></t:table-cell></t:table-row>'
            cols = '<t:table-header-columns><t:table-column t:default-cell-style-name="ActualHeader" t:style-name="W127"/></t:table-header-columns><t:table-columns><t:table-column t:default-cell-style-name="Header" t:style-name="W40"/></t:table-columns>'
            source, changed, moved = [root/n for n in ['source.ods','changed.ods','moved.ods']]
            fixture(source, cols+row, defs)
            fixture(changed, cols.replace('ActualHeader','Header').replace('style-name="W127"','style-name="W40"')+row, defs)
            self.assertEqual(typed(source), typed(changed))
            self.assertNotEqual(effective_cells(source), effective_cells(changed))
            self.assertEqual(fixed_widths(source), [127,40])
            self.assertEqual(fixed_widths(changed), [40,40])
            fixture(moved, cols.replace('table-header-columns','TEMP').replace('table-columns','table-header-columns').replace('TEMP','table-columns')+row, defs)
            self.assertEqual(effective_cells(source), effective_cells(moved))
            self.assertEqual(fixed_widths(source), fixed_widths(moved))
            invalid = root/'invalid.ods'
            fixture(invalid, '<t:table-column-group>'+cols+'</t:table-column-group>'+row, defs)
            with self.assertRaises(ValueError): effective_cells(invalid)
            with self.assertRaises(ValueError): fixed_widths(invalid)

    def xml(self, root, name, body):
        target = root/name
        target.write_bytes(package((PREFIX+body+SUFFIX).encode()))
        return typed(target)

    def test_header_container_text_order_and_merge_mutations_are_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            header = '<t:table-header-rows><t:table-row><t:table-cell o:value-type="string"><x:p>real header</x:p></t:table-cell></t:table-row></t:table-header-rows>'
            body = '<t:table-rows><t:table-row><t:table-cell o:value-type="float" o:value="7"/></t:table-row></t:table-rows>'
            original = self.xml(root,'header.ods',header+body)
            self.assertEqual(original['Input']['0,0']['text'], 'real header')
            self.assertEqual(original['Input']['1,0']['value'], decimal_identity('7'))
            self.assertNotEqual(original, self.xml(root,'changed.ods',header.replace('real header','CORRUPTED')+body))
            self.assertNotEqual(original, self.xml(root,'moved.ods',body+header))
            merged = '<t:table-header-rows><t:table-row><t:table-cell t:number-columns-spanned="2"/><t:covered-table-cell/></t:table-row></t:table-header-rows>'
            self.assertNotEqual(self.xml(root,'merge.ods',merged), self.xml(root,'badmerge.ods',merged.replace('spanned="2"','spanned="3"')))
            with self.assertRaises(ValueError):
                self.xml(root,'unknown.ods','<t:table-row-group>'+body+'</t:table-row-group>')

    def test_type_unit_offset_and_duration_sign_mutations_are_observed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for i,(original,changed) in enumerate([
                ('o:value-type="currency" o:value="12.5" o:currency="USD"','o:value-type="currency" o:value="12.5" o:currency="CNY"'),
                ('o:value-type="percentage" o:value="0.25"','o:value-type="float" o:value="0.25"'),
                ('o:value-type="date" o:date-value="2026-10-26T01:30:00+08:00"','o:value-type="date" o:date-value="2026-10-26T01:30:00+09:00"'),
                ('o:value-type="time" o:time-value="-PT1H"','o:value-type="time" o:time-value="PT1H"'),
            ]):
                a=self.xml(root,str(i)+'a.ods','<t:table-row><t:table-cell '+original+'/></t:table-row>')
                b=self.xml(root,str(i)+'b.ods','<t:table-row><t:table-cell '+changed+'/></t:table-row>')
                self.assertNotEqual(a,b)

    def test_legacy_odfpy_comparator_does_not_round_actual_input(self):
        from odf.table import TableCell
        from verify_external import cell_value, expected_cell
        self.assertNotEqual(cell_value(TableCell(valuetype='float', value='-0')), expected_cell(('number',0.0)))
        self.assertNotEqual(cell_value(TableCell(valuetype='float', value='9007199254740993')), expected_cell(('number',9007199254740992)))
        self.assertEqual(cell_value(TableCell(valuetype='float', value='1.00')), expected_cell(('number',1.0)))


if __name__ == '__main__':
    unittest.main()
