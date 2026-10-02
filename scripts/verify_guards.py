#!/usr/bin/env python3
"""Exercise public verifier CLIs with controlled invalid runtime/candidate inputs."""
import argparse, json, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--moon', required=True, type=Path)
    ap.add_argument('--candidate-report', required=True, type=Path)
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args(); out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    results = []
    def run(name, command, env, message):
        r = subprocess.run([str(x) for x in command], cwd=ROOT, env=env, text=True, capture_output=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(r.stdout)
        (out / (name + '.stderr.txt')).write_text(r.stderr)
        path = out / name / ('acceptance.json' if name == 'runtime-drift' else 'registry.json')
        report = json.loads(path.read_text())
        assert r.returncode == 1 and report['status'] == 'FAIL' and message in report['error'], (name, r.returncode, report)
        # Both guards must stop before normal tests or any registry update.
        forbidden = {'test', 'registry-update', 'consumer-check'}
        assert not forbidden.intersection(s['name'] for s in report['steps'])
        results.append({'name':name, 'status':'PASS', 'expected_cli_exit_code':1, 'observed_error':report['error']})
    with tempfile.TemporaryDirectory(prefix='moonods-guard-') as temp:
        fake = Path(temp) / 'node'
        fake.write_text("#!/bin/sh\nprintf '%s\\n' 'v0.0.0'\n"); fake.chmod(0o755)
        env = os.environ.copy(); env['PATH'] = temp + os.pathsep + env['PATH']
        run('runtime-drift', [sys.executable, ROOT/'scripts/acceptance.py', '--moon', args.moon,
                             '--output', out/'runtime-drift'], env, 'Node/Python differs from TOOLCHAIN.lock')
    run('wrong-registry-candidate', [sys.executable, ROOT/'scripts/verify_registry.py',
        '--sdk', args.moon.resolve().parent.parent, '--candidate-report', args.candidate_report.resolve(),
        '--output', out/'wrong-registry-candidate'], os.environ.copy(), 'not the historical published 0.1.0 candidate')
    final = {'status':'PASS', 'controls':results, 'network_calls_performed':False, 'global_environment_changed':False}
    (out/'guards.json').write_text(json.dumps(final,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(final,ensure_ascii=False))

if __name__ == '__main__': main()
