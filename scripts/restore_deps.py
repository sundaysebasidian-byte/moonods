#!/usr/bin/env python3
"""Reuse the bundled exact dependency sources; writes only this project."""
import hashlib, json, zipfile
from pathlib import Path, PurePosixPath
from verify_deps import ROOT, verify

for item in json.loads((ROOT / 'DEPENDENCIES.lock.json').read_text()).values():
    archive = ROOT / item['archive']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256']
    target = ROOT / '.mooncakes' / item['module']
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            p = PurePosixPath(name)
            if p.is_absolute() or '..' in p.parts or '\\' in name:
                raise SystemExit('unsafe dependency archive path')
            if name.endswith('/'): continue
            out = target / p
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(z.read(name))
print(json.dumps(verify(), indent=2))
