#!/usr/bin/env python3
"""Validate exact dependency contents; checks remain active under python -O."""
import hashlib
import json
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_path(root, name):
    """Reject traversal, ambiguous ZIP names and symlinks before reading/writing."""
    p = PurePosixPath(name)
    require(bool(name) and not p.is_absolute() and '\\' not in name
            and all(part not in ('', '.', '..') for part in name.split('/')),
            'unsafe dependency path: ' + name)
    target = root
    for part in p.parts:
        target = target / part
        require(not target.is_symlink(), 'dependency symlink forbidden: ' + str(target))
    return target


def installed_files(source):
    result = set()
    if not source.exists():
        return result
    require(source.is_dir(), 'dependency target is not a directory')
    # Do not follow symbolic-link directories, and reject them rather than omit.
    for path in source.rglob('*'):
        require(not path.is_symlink(), 'dependency symlink forbidden: ' + str(path))
        require(path.is_dir() or path.is_file(), 'nonregular dependency entry: ' + str(path))
        if path.is_file():
            result.add(path.relative_to(source).as_posix())
    return result


def verify(root=ROOT):
    lock = json.loads(safe_path(root, 'DEPENDENCIES.lock.json').read_text())
    for item in lock.values():
        archive = safe_path(root, item['archive'])
        require(hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256'],
                'dependency archive mismatch')
        source = safe_path(root, '.mooncakes/' + item['module'])
        expected = item['files_sha256']
        require(installed_files(source) == set(expected), 'dependency file set mismatch')
        for name, digest in expected.items():
            path = safe_path(source, name)
            require(hashlib.sha256(path.read_bytes()).hexdigest() == digest,
                    'dependency source mismatch: ' + str(path))
    return {k: {'version': v['version'], 'sha256': v['sha256']} for k, v in lock.items()}


if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))
