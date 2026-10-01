#!/usr/bin/env python3
"""Package tracked source, committed evidence, examples and local Git history."""
import argparse, hashlib, json, subprocess, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--output', type=Path, default=ROOT.parent / 'outputs/MoonODS-source-0.1.0.zip')
    args = p.parse_args()
    if git('status', '--porcelain', '--untracked-files=no').strip():
        raise SystemExit('Commit reviewed source/evidence before packaging')
    output = args.output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    names = [x.decode() for x in git('ls-files', '-z').split(b'\0') if x]
    payload = {n: (ROOT / n).read_bytes() for n in names}
    for name in ['sales', 'experiment', 'formulas', 'edge']:
        n = f'examples/generated/{name}.ods'; payload[n] = (ROOT / n).read_bytes()
    head = git('rev-parse', 'HEAD').decode().strip()
    with tempfile.TemporaryDirectory() as temp:
        bundle = Path(temp) / 'moonods-history.bundle'
        subprocess.run(['git', 'bundle', 'create', str(bundle), '--all'], cwd=ROOT, check=True)
        payload['moonods-history.bundle'] = bundle.read_bytes()
    payload['GIT_HISTORY.txt'] = git('log', '--reverse', '--format=%H %s')
    state = {'head': head, 'commit_count': int(git('rev-list', '--count', 'HEAD')),
             'remote_configured': bool(git('remote').strip()),
             'files_sha256': {n: hashlib.sha256(d).hexdigest() for n,d in sorted(payload.items())}}
    payload['SOURCE_STATE.json'] = (json.dumps(state, ensure_ascii=False, indent=2)+'\n').encode()
    with zipfile.ZipFile(output, 'w') as z:
        for name,data in sorted(payload.items()):
            i = zipfile.ZipInfo('MoonODS/' + name, (1980,1,1,0,0,0))
            i.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(i, data)
    print(json.dumps({'file': str(output), 'bytes': output.stat().st_size(), 'head': head,
                      'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}, indent=2))

if __name__ == '__main__': main()
