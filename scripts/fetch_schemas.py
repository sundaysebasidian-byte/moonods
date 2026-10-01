#!/usr/bin/env python3
"""Download untouched OASIS schemas and verify recorded SHA256 before use."""
from pathlib import Path
import argparse, hashlib, urllib.request

BASE = 'https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/'
SCHEMAS = {
    'document': ('OpenDocument-v1.3-schema.rng', '40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6'),
    'manifest': ('OpenDocument-v1.3-manifest-schema.rng', '8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17'),
}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, default=Path('.schemas'))
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for key, (name, expected) in SCHEMAS.items():
        target = args.output / f'{key}.rng'
        data = target.read_bytes() if target.exists() else urllib.request.urlopen(BASE + name, timeout=60).read()
        actual = hashlib.sha256(data).hexdigest()
        if actual != expected:
            raise SystemExit(f'Schema checksum mismatch for {name}; refusing to validate against unknown bytes')
        target.write_bytes(data)
        print(f'{name}: SHA256 {actual} verified')

if __name__ == '__main__':
    main()
