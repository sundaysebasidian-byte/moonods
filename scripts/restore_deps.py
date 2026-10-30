#!/usr/bin/env python3
"""Restore bundled locked dependencies after validating every input and target.

No concurrent/adversarial filesystem writer is supported. No links are followed.
Validation failures occur before writes; ordinary I/O failures are not transactional.
"""
import hashlib
import json
import stat
import zipfile
from verify_deps import ROOT, verify, require, safe_path, installed_files


def restore(root=ROOT):
    lock = json.loads(safe_path(root, 'DEPENDENCIES.lock.json').read_text())
    pending = []
    for item in lock.values():
        archive = safe_path(root, item['archive'])
        require(hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256'],
                'dependency archive mismatch')
        target = safe_path(root, '.mooncakes/' + item['module'])
        expected = item['files_sha256']
        require(installed_files(target) <= set(expected), 'unexpected installed dependency files')
        seen = set()
        with zipfile.ZipFile(archive) as z:
            for entry in z.infolist():
                name = entry.filename
                out = safe_path(target, name[:-1] if entry.is_dir() else name)
                mode = entry.external_attr >> 16
                require(not stat.S_ISLNK(mode), 'archive symlink forbidden')
                if entry.is_dir():
                    continue
                require(stat.S_IFMT(mode) in (0, stat.S_IFREG), 'nonregular archive entry')
                require(name not in seen and name in expected, 'archive file set mismatch')
                seen.add(name)
                data = z.read(entry)
                require(hashlib.sha256(data).hexdigest() == expected[name],
                        'archive member digest mismatch: ' + name)
                require(not out.exists() or out.is_file(), 'dependency destination is not a file')
                pending.append((item['module'], name, data))
        require(seen == set(expected), 'archive missing locked files')
    for module, name, data in pending:
        # Recheck the entire target path immediately before each write.
        out = safe_path(root, '.mooncakes/' + module + '/' + name)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
    return verify(root)


if __name__ == '__main__':
    print(json.dumps(restore(), indent=2))
