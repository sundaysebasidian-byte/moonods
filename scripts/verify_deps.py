#!/usr/bin/env python3
"""Validate installed dependency sources against untouched registry archives."""
import hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def verify():
    lock = json.loads((ROOT / 'DEPENDENCIES.lock.json').read_text())
    for item in lock.values():
        archive = ROOT / item['archive']
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256'], 'dependency archive mismatch'
        source = ROOT / '.mooncakes' / item['module']
        for name, digest in item['files_sha256'].items():
            assert hashlib.sha256((source / name).read_bytes()).hexdigest() == digest, f'dependency source mismatch: {source / name}'
    return {k: {'version': v['version'], 'sha256': v['sha256']} for k,v in lock.items()}

if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))
