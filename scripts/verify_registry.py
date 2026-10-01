#!/usr/bin/env python3
"""Fetch published 0.1.0 in an empty registry home; never use moon.work."""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys
from pathlib import Path
from verify_consumer_outputs import verify_generated

ROOT = Path(__file__).resolve().parent.parent

def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--candidate-report', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    work = out / 'isolated-work'
    if work.exists(): raise SystemExit('Use a new output directory; cache must start empty')
    work.mkdir(); home = work / 'sdk-home'; home.mkdir()
    # Reuse only the installed compiler and bundled core, not credentials/cache.
    for name in ['bin', 'lib', 'include']: (home / name).symlink_to(args.sdk.resolve() / name)
    (home / 'registry').mkdir()
    consumer = work / 'consumer'
    shutil.copytree(ROOT / 'fixtures/reuse-consumer', consumer,
                    ignore=shutil.ignore_patterns('_build', '.mooncakes'))
    env = os.environ.copy(); env['MOON_HOME'] = str(home); env['RUST_LOG'] = 'error'
    moon = home / 'bin/moon'
    steps = []
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'steps': steps, 'scope': 'Real published registry consumption with initially empty registry index/package cache',
              'local_workspace': False, 'initial_registry_entries': [],
              'credentials_copied': False, 'existing_sdk_core_reused': True,
              'not_measured': ['fresh machine', 'office applications', 'other compiler backends']}
    def run(name, argv):
        r = subprocess.run([str(a) for a in argv], cwd=consumer, env=env,
                           capture_output=True, text=True, timeout=180)
        (out / (name + '.stdout.txt')).write_text(r.stdout)
        (out / (name + '.stderr.txt')).write_text(r.stderr)
        steps.append({'name': name, 'command': [str(a) for a in argv],
                      'exit_code': r.returncode, 'status': 'PASS' if r.returncode == 0 else 'FAIL'})
        if r.returncode: raise RuntimeError(name + ' failed; retained logs')
        return r.stdout + r.stderr
    try:
        assert not list((home / 'registry').iterdir())
        assert not (consumer / 'moon.work').exists()
        run('registry-update', [moon, 'update'])
        run('consumer-format', [moon, 'fmt', '--check', 'src'])
        run('consumer-check', [moon, 'check', '--target', 'js', '-j', '1', '--deny-warn'])
        installed = consumer / '.mooncakes/sundaysebasidian-byte/moonods'
        expected = json.loads(args.candidate_report.read_text())['candidate']['all_files_sha256']
        actual = hashes(installed)
        assert actual == expected, 'Registry package bytes differ from approved candidate'
        report['published_package'] = {'module': 'sundaysebasidian-byte/moonods', 'version': '0.1.0',
            'file_count': len(actual), 'all_files_sha256': actual,
            'all_registry_bytes_match_publish_candidate': True}
        run('consumer-build', [moon, 'build', '--target', 'js', '-j', '1', '--deny-warn'])
        tests = run('consumer-test', [moon, 'test', '--target', 'js', '-j', '1', '--deny-warn', 'src'])
        m = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)', tests)
        assert m and m[1] == m[2] and m[3] == '0' and int(m[1]) >= 4
        report['tests'] = {'total': int(m[1]), 'passed': int(m[2]), 'failed': int(m[3])}
        run('consumer-first', [moon, 'run', '--target', 'js', '-j', '1', 'src'])
        generated = consumer / 'generated'; first = hashes(generated)
        assert set(first) == {'business.ods', 'laboratory.ods', 'declarations.ods'}
        run('consumer-second', [moon, 'run', '--target', 'js', '-j', '1', 'src'])
        assert hashes(generated) == first
        report['independent_reader'] = verify_generated(generated, ROOT / '.schemas')
        report['cross_process_determinism'] = {'status': 'PASS', 'sha256': first}
        for path in generated.glob('*.ods'): shutil.copyfile(path, out / path.name)
        report['status'] = 'PASS'
    except Exception as e:
        report['status'] = 'FAIL'; report['error'] = str(e)
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'registry.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1

if __name__ == '__main__': sys.exit(main())
