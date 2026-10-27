"""Independent exact lexical-number identities; never use float for comparison.

binary64_expected is an explicit policy for a caller checking a documented
binary64 conversion, not the default identity and not financial arithmetic.
"""
from decimal import Decimal, InvalidOperation
import math
import re

NUMBER = re.compile(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z')


def decimal_identity(raw):
    if not isinstance(raw, str) or len(raw) > 1024 or not NUMBER.fullmatch(raw):
        raise ValueError('invalid bounded ODF numeric lexical form')
    try:
        number = Decimal(raw)
    except InvalidOperation as exc:
        raise ValueError('invalid decimal') from exc
    if not number.is_finite():
        raise ValueError('nonfinite numeric value')
    sign, digits, exponent = number.as_tuple()
    if not any(digits):
        return '-0' if sign else '0'
    digits = list(digits)
    while digits[-1] == 0:
        digits.pop()
        exponent += 1
    return ('-' if sign else '+') + ''.join(map(str, digits)) + 'e' + str(exponent)


def binary64_expected(raw):
    decimal_identity(raw)
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError('binary64 overflow')
    if value == 0.0 and Decimal(raw) != 0:
        raise ValueError('binary64 nonzero underflow')
    return decimal_identity(repr(value))


def boolean_identity(raw):
    if raw in ('true', '1'):
        return 'true'
    if raw in ('false', '0'):
        return 'false'
    raise ValueError('invalid ODF boolean')


def typed_observation(observation):
    result = {}
    fields = ['value-type', 'value', 'boolean-value', 'date-value', 'time-value',
              'currency', 'formula', 'number-columns-spanned',
              'number-rows-spanned', 'covered']
    for sheet, cells in observation['sheets'].items():
        result[sheet] = {}
        for position, cell in cells.items():
            record = {k: cell[k] for k in fields if k in cell}
            kind = cell.get('value-type')
            if kind == 'string':
                record['text'] = cell['text']
            if kind in ('float', 'currency', 'percentage'):
                record['value'] = decimal_identity(cell['value'])
            if kind == 'boolean':
                record['boolean-value'] = boolean_identity(cell['boolean-value'])
            result[sheet][position] = record
    return result


def expected_number(value):
    """Known test expectation only; actual XML values never pass through float."""
    return decimal_identity(value if isinstance(value, str) else repr(value))


def normalize_expected(tree):
    if isinstance(tree, dict):
        result = {k: normalize_expected(v) for k, v in tree.items()}
        if result.get('value-type') in ('float', 'percentage', 'currency') and 'value' in result:
            result['value'] = expected_number(result['value'])
        return result
    if isinstance(tree, list):
        return [normalize_expected(v) for v in tree]
    return tree
