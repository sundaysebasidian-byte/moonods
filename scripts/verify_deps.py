#!/usr/bin/env python3
"""Validate exact dependency contents; checks remain active under python -O."""
import hashlib
import json
import stat
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_path(root, name):
    """Reject traversal, ambiguous ZIP names and links before reading/writing."""
    p = PurePosixPath(name)
    require(bool(name) and not p.is_absolute() and '\\' not in name
            and all(part not in ('', '.', '..') for part in name.split('/')),
            'unsafe dependency path: ' + name)
    root = Path(root)
    require(not root.is_symlink() and (not root.exists() or root.is_dir()),
            'dependency root must be an unlinked directory')
    target = root
    for index, part in enumerate(p.parts):
        target = target / part
        try:
            info = target.lstat()
        except FileNotFoundError:
            continue
        require(not stat.S_ISLNK(info.st_mode), 'dependency symlink forbidden: ' + str(target))
        require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode),
                'nonregular dependency path: ' + str(target))
        require(not stat.S_ISREG(info.st_mode) or info.st_nlink == 1,
                'dependency hardlink forbidden: ' + str(target))
        require(index == len(p.parts) - 1 or stat.S_ISDIR(info.st_mode),
                'dependency parent is not a directory: ' + str(target))
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
            require(path.stat().st_nlink == 1, 'dependency hardlink forbidden: ' + str(path))
            result.add(path.relative_to(source).as_posix())
    return result


def dependency_targets(root, lock):
    """Require disjoint installed module trees before inspecting or writing files."""
    targets = {}
    for key, item in lock.items():
        target = safe_path(root, '.mooncakes/' + item['module'])
        for previous in targets.values():
            require(not (target == previous or target.is_relative_to(previous)
                         or previous.is_relative_to(target)),
                    'overlapping dependency module roots: ' + str(target))
        targets[key] = target
    return targets


def verify(root=ROOT):
    lock = json.loads(safe_path(root, 'DEPENDENCIES.lock.json').read_text())
    targets = dependency_targets(root, lock)
    for key, item in lock.items():
        archive = safe_path(root, item['archive'])
        require(hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256'],
                'dependency archive mismatch')
        source = targets[key]
        expected = item['files_sha256']
        require(installed_files(source) == set(expected), 'dependency file set mismatch')
        for name, digest in expected.items():
            path = safe_path(source, name)
            require(hashlib.sha256(path.read_bytes()).hexdigest() == digest,
                    'dependency source mismatch: ' + str(path))
    return {k: {'version': v['version'], 'sha256': v['sha256']} for k, v in lock.items()}


if __name__ == '__main__':
    print(json.dumps(verify(), indent=2))
