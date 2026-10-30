#!/usr/bin/env python3
"""Install only the locked Linux x86_64 SDK/core in a new project subdirectory.

No global install, shell installer, latest fallback, registry dependency or SDK
upgrade. Both archives must verify before creating the destination. Checksums
pin previously verified official bytes; they are not vendor-signed attestations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ('moon', 'moonc', 'moonrun', 'moonfmt', 'mooninfo', 'mooncake', 'moon-lsp',
         'moon_cove_report', 'moon-wasm-opt', 'moonc-prove', 'moon-ide', 'moon-cram',
         'moondoc', 'internal/tcc')


def official_url(url):
    parsed = urllib.parse.urlsplit(url)
    return (parsed.scheme == 'https' and parsed.netloc == 'cli.moonbitlang.com'
            and not parsed.query and not parsed.fragment)


def checked_lock(path):
    lock = json.loads(path.read_text())
    release = urllib.parse.quote(lock['compiler'], safe='')
    expected = {
        'sdk': f'https://cli.moonbitlang.com/binaries/{release}/moonbit-linux-x86_64.tar.gz',
        'core': f'https://cli.moonbitlang.com/cores/core-{release}.tar.gz',
    }
    for part, url in expected.items():
        if lock[part + '_url'] != url or not official_url(url):
            raise ValueError('archive URL must match the fixed official version')
        if not re.fullmatch('[0-9a-f]{64}', lock[part + '_sha256']):
            raise ValueError('invalid pinned SHA256')
    return lock


def destination(path):
    dest = path.resolve()
    if dest == ROOT or not dest.is_relative_to(ROOT):
        raise ValueError('destination must be a new project-local subdirectory')
    if dest.exists():
        raise ValueError('destination exists; inspect previous outcome, do not overwrite')
    return dest


class OfficialRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not official_url(newurl):
            raise ValueError('redirect away from the locked official HTTPS host')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, path, digest):
    opener = urllib.request.build_opener(OfficialRedirect())
    sha = hashlib.sha256()
    size = 0
    with opener.open(url, timeout=120) as response, path.open('xb') as output:
        if not official_url(response.url):
            raise ValueError('unexpected response URL')
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > 512 * 1024 * 1024:
                raise ValueError('archive exceeds bounded download ceiling')
            sha.update(chunk)
            output.write(chunk)
    if sha.hexdigest() != digest:
        raise ValueError('archive SHA256 mismatch; destination not created')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dest', required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        parser.error('locked archives require Linux x86_64')
    lock = checked_lock(ROOT / 'TOOLCHAIN.lock')
    dest = destination(args.dest)
    with tempfile.TemporaryDirectory(prefix='moonods-sdk-') as tmp:
        archives = []
        for part in ('sdk', 'core'):
            path = Path(tmp) / (part + '.tar.gz')
            download(lock[part + '_url'], path, lock[part + '_sha256'])
            archives.append((part, path))
        # Recheck to avoid replacing an intervening actor's directory.
        destination(dest)
        dest.mkdir(parents=True, exist_ok=False)
        for part, path in archives:
            target = dest if part == 'sdk' else dest / 'lib'
            target.mkdir(exist_ok=True)
            with tarfile.open(path, 'r:gz') as archive:
                archive.extractall(target, filter='data')
    for name in TOOLS:
        tool = dest / 'bin' / name
        if tool.is_symlink() or not tool.is_file():
            raise RuntimeError('missing/unsafe SDK executable: ' + name)
        tool.chmod(tool.stat().st_mode | 0o111)
    env = {**os.environ, 'MOON_HOME': str(dest),
           'PATH': str(dest / 'bin') + os.pathsep + os.environ.get('PATH', '')}
    actual = subprocess.check_output([str(dest / 'bin/moonc'), '-v'], env=env, text=True).strip()
    if not actual.startswith('v' + lock['compiler'] + ' '):
        raise RuntimeError('unexpected compiler version after extraction')
    # Bound workspace discovery to the newly extracted SDK core. Without this,
    # a project-local SDK inherits the parent project's moon.work before its
    # dependencies exist. Do not modify that parent workspace or skip bundling.
    core_workspace = dest / 'lib/core/moon.work'
    with core_workspace.open('x') as workspace:
        workspace.write('members = ["."]\n')
    subprocess.run([str(dest / 'bin/moon'), 'bundle', '--all'], cwd=dest / 'lib/core', env=env, check=True)
    print('Verified project-local SDK/core installed; no global settings modified')


if __name__ == '__main__':
    main()
