"""Decode the fixed consumer's stdout host adapter, without ODS interpretation."""
import base64, hashlib

def decode_output(text, destination):
    destination.mkdir(parents=True, exist_ok=True)
    records = {}
    for line in text.splitlines():
        if not line.startswith('MOONODS_ODS:'): continue
        _, name, encoded = line.split(':', 2)
        if name not in ['business','laboratory','declarations'] or name in records:
            raise ValueError('Unexpected or duplicate fixed consumer output')
        if len(encoded) > 44739244: raise ValueError('Encoded package exceeds 32MiB envelope')
        data = base64.b64decode(encoded, validate=True)
        if len(data) > 33554432: raise ValueError('Package exceeds 32MiB envelope')
        (destination / (name + '.ods')).write_bytes(data)
        records[name + '.ods'] = hashlib.sha256(data).hexdigest()
    if set(records) != {'business.ods','laboratory.ods','declarations.ods'}:
        raise ValueError('Missing fixed consumer output')
    return records
