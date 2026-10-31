#!/usr/bin/env python3
"""Package clean tracked source for local testing; never include Git history.

No concurrent worktree or filesystem writer is supported.
"""
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
    if 'SOURCE_STATE.json' in names:
        raise SystemExit('SOURCE_STATE.json is reserved for export metadata')
    payload = {n: (ROOT / n).read_bytes() for n in names}
    head = git('rev-parse', 'HEAD').decode().strip()
    # Index flags can hide modified worktree bytes from `git status`.
    # Bind every exported byte to HEAD, not merely to the index's clean hint.
    entries = {}
    for entry in git('ls-tree', '-r', '-z', head).split(b'\0'):
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        mode, kind, oid = metadata.decode().split()
        entries[name.decode()] = (mode, kind, oid)
    if set(entries) != set(payload):
        raise SystemExit('Tracked file set does not match HEAD')
    object_format = git('rev-parse', '--show-object-format').decode().strip()
    if object_format not in ('sha1', 'sha256'):
        raise SystemExit('Unsupported Git object format')
    for name, data in payload.items():
        mode, kind, oid = entries[name]
        actual = hashlib.new(object_format, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if kind != 'blob' or mode not in ('100644', '100755') or actual != oid:
            raise SystemExit('Worktree bytes do not match reviewed HEAD: ' + name)
    payload['SOURCE_STATE.json'] = json.dumps({
        'head': head,
        'files_sha256': {n: hashlib.sha256(data).hexdigest() for n, data in sorted(payload.items())},
        'scope': 'tracked source only; no Git history, SDK, cache or historical audit evidence',
    }, ensure_ascii=False, indent=2).encode()
    output = a.output.resolve()
    git_dirs = [(ROOT / '.git').resolve()]
    for flag in ('--git-dir', '--git-common-dir'):
        path = Path(git('rev-parse', flag).decode().strip())
        git_dirs.append((path if path.is_absolute() else ROOT / path).resolve())
    if any(output == path or output.is_relative_to(path) for path in git_dirs):
        raise SystemExit('Output must not target Git metadata')
    for name in names:
        source = ROOT / name
        if output == source.resolve() or (output.exists() and output.samefile(source)):
            raise SystemExit('Output must not replace or alias tracked source: ' + name)
    if output.exists() and (not output.is_file() or output.stat().st_nlink != 1):
        raise SystemExit('Output must be an unlinked regular file or a new path')
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
