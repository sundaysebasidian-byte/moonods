"""Check a private source export's complete payload, not just listed hashes.

This is internal consistency checking, not authentication of a Git commit.
The caller must supply a freshly extracted tree with no concurrent writers.
"""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate source manifest key: ' + key)
        result[key] = value
    return result


def _regular(path):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('source manifest requires regular files: ' + str(path))


def verify_source_manifest(root):
    """Return metadata only if its file set and every SHA-256 match the tree."""
    root = Path(root)
    if not stat.S_ISDIR(root.lstat().st_mode):
        raise ValueError('source manifest requires a real directory')
    metadata = root / 'SOURCE_STATE.json'
    _regular(metadata)
    state = json.loads(metadata.read_text(encoding='utf-8'), object_pairs_hook=_unique_object)
    if not isinstance(state, dict):
        raise ValueError('source manifest must be an object')
    head = state.get('head')
    if not isinstance(head, str) or not re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', head):
        raise ValueError('invalid source manifest commit')
    expected = state.get('files_sha256')
    if not isinstance(expected, dict) or not expected:
        raise ValueError('source manifest must list a nonempty file set')
    for name, digest in expected.items():
        parts = PurePosixPath(name).parts
        if (not parts or name.startswith('/') or '\\' in name or ':' in name
                or any(p in ('.', '..') for p in parts) or name != '/'.join(parts)
                or name == 'SOURCE_STATE.json'):
            raise ValueError('unsafe source manifest path: ' + name)
        if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('invalid source manifest SHA-256: ' + name)

    actual = {}

    def walk_error(error):
        raise error

    for directory, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        parent = Path(directory)
        for name in dirs:
            if not stat.S_ISDIR((parent / name).lstat().st_mode):
                raise ValueError('source manifest refuses linked directories')
        for name in files:
            path = parent / name
            _regular(path)
            relative = path.relative_to(root).as_posix()
            if relative != 'SOURCE_STATE.json':
                actual[relative] = path
    missing = sorted(set(expected) - set(actual))
    unlisted = sorted(set(actual) - set(expected))
    if missing or unlisted:
        raise ValueError('source manifest file set mismatch: missing=' + repr(missing)
                         + ', unlisted=' + repr(unlisted))
    for name, path in actual.items():
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected[name]:
            raise ValueError('source manifest mismatch: ' + name)
    return state
