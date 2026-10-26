#!/usr/bin/env python3
"""Package clean tracked source for local testing; never include Git history."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if git('status', '--porcelain', '--untracked-files=no').strip():
        raise SystemExit('Commit reviewed source before packaging')
    names = [n.decode() for n in git('ls-files', '-z').split(b'\0') if n]
    forbidden = {'evidence', '_build', '.git', '.mooncakes', '__pycache__'}
    if any(forbidden.intersection(Path(n).parts) or n.endswith(('.bundle', '.wasm', '.log'))
           or (ROOT / n).is_symlink() for n in names):
        raise SystemExit('Source export refuses historical evidence, generated binaries or links')
    payload = {n: (ROOT / n).read_bytes() for n in names}
    head = git('rev-parse', 'HEAD').decode().strip()
    payload['SOURCE_STATE.json'] = json.dumps({
        'head': head,
        'files_sha256': {n: hashlib.sha256(data).hexdigest() for n, data in sorted(payload.items())},
        'scope': 'tracked source only; no Git history, SDK, cache or historical audit evidence',
    }, ensure_ascii=False, indent=2).encode()
    output = a.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w') as z:
        for n, data in sorted(payload.items()):
            info = zipfile.ZipInfo('MoonODS/' + n, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    print(json.dumps({'head': head, 'path': str(output), 'files': len(payload),
                      'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
