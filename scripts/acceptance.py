#!/usr/bin/env python3
"""Serial, fail-closed reproducible checks. Does not install tools or publish."""
import argparse, datetime, hashlib, json, os, platform, re, shutil, subprocess, sys
from importlib.metadata import version
from pathlib import Path
from verify_deps import ROOT, verify

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--moon', default=os.environ.get('MOON_BIN') or shutil.which('moon'))
    p.add_argument('--output', type=Path, default=ROOT / 'evidence' / 'current')
    args = p.parse_args()
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy(); env['RUST_LOG'] = 'error'
    steps = []
    def run(name, argv):
        result = subprocess.run([str(x) for x in argv], cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(result.stdout)
        (out / (name + '.stderr.txt')).write_text(result.stderr)
        steps.append({'name': name, 'command': [str(x) for x in argv], 'exit_code': result.returncode,
                      'status': 'PASS' if result.returncode == 0 else 'FAIL'})
        if result.returncode: raise RuntimeError(f'{name} failed; inspect saved logs')
        return result.stdout + result.stderr
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'platform': platform.platform(), 'python': platform.python_version(), 'steps': steps,
              'scope': 'JS backend core + examples + independent package/schema/reader checks',
              'not_run_by_this_script': ['LibreOffice', 'Excel', 'Numbers', 'WPS', 'remote CI', 'native/wasm backends', 'peak RSS and performance']}
    source_files = list(ROOT.glob('*.mbt')) + list((ROOT / 'examples').rglob('*.mbt')) + list((ROOT / 'tests').rglob('*.mbt')) + list((ROOT / 'fixtures').rglob('*.mbt')) + list((ROOT / 'scripts').glob('*.py'))
    source_files = [f for f in source_files if '_build' not in f.parts]
    report['source_sha256'] = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(source_files)}
    try:
        if not args.moon: raise RuntimeError('Existing moon binary required; no automatic installation')
        moon = Path(args.moon).resolve()
        compiler = moon.parent / 'moonc'
        compiler_version = run('moonc-version', [compiler, '-v'])
        if not compiler_version.startswith('v0.10.14+7d59c7ec9 '): raise RuntimeError('Compiler differs from TOOLCHAIN.lock')
        tool_version = run('moon-version', [moon, 'version'])
        if not tool_version.startswith('moon 0.1.20260920 (914d7da '): raise RuntimeError('Moon build tool differs from TOOLCHAIN.lock')
        node_version = run('node-version', ['node', '--version']).strip()
        verifier_versions = {k: version(k) for k in ['odfpy', 'lxml', 'defusedxml']}
        report['runtime_versions'] = {'node': node_version, 'python': platform.python_version(), **verifier_versions}
        if node_version != 'v24.18.0' or platform.python_version() != '3.13.14':
            raise RuntimeError('Node/Python differs from TOOLCHAIN.lock')
        if verifier_versions != {'odfpy': '1.4.1', 'lxml': '6.0.2', 'defusedxml': '0.7.1'}:
            raise RuntimeError('Verifier dependencies differ from TOOLCHAIN.lock')
        report['dependencies'] = verify()
        run('format', [moon, 'fmt', '--check'])
        run('check', [moon, 'check', '--target', 'js', '-j', '1', '--deny-warn'])
        run('build', [moon, 'build', '--target', 'js', '-j', '1', '--deny-warn'])
        tests = run('test', [moon, 'test', '--target', 'js', '-j', '1', '--deny-warn'])
        m = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)', tests)
        if not m or int(m[1]) < 30 or m[1] != m[2] or m[3] != '0': raise RuntimeError('Missing or incomplete test summary')
        report['unit_tests'] = {'total': int(m[1]), 'passed': int(m[2]), 'failed': int(m[3])}
        hashes = lambda: {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in (ROOT / 'examples/generated').glob('*.ods')}
        run('examples-first', [moon, 'run', '--target', 'js', '-j', '1', 'examples/generate'])
        first = hashes()
        run('examples-second', [moon, 'run', '--target', 'js', '-j', '1', 'examples/generate'])
        if set(first) != {'sales.ods', 'experiment.ods', 'formulas.ods', 'edge.ods'} or first != hashes():
            raise RuntimeError('Cross-process output determinism failed')
        report['cross_process_determinism'] = {'status': 'PASS', 'sha256': first}
        office_path = ROOT / 'evidence/office-2026-10-01-fixed/excel.json'
        if office_path.exists():
            office = json.loads(office_path.read_text())
            expected = {'moonods-' + name: digest for name, digest in first.items()}
            report['separate_office_evidence'] = {
                'file': str(office_path.relative_to(ROOT)),
                'sha256': hashlib.sha256(office_path.read_bytes()).hexdigest(),
                'provenance': 'Previously executed native application read; not rerun by this script',
                'application': office['application'], 'version': office['version'],
                'status': office['status'], 'normal_cases': office['normal_cases'],
                'boundaries': office['boundaries'],
                'matches_current_generated_ods': office['inputs_unchanged_sha256'] == expected,
            }
            if not report['separate_office_evidence']['matches_current_generated_ods']:
                report['separate_office_evidence']['status'] = 'STALE INPUTS'
        run('schema-bytes', [sys.executable, ROOT / 'scripts/fetch_schemas.py'])
        run('external', [sys.executable, ROOT / 'scripts/verify_external.py', '--report', out / 'external.json'])
        compatibility_file = ROOT / 'examples/compatibility/generated/compatibility.ods'
        run('compatibility-first', [moon, 'run', '--target', 'js', '-j', '1', 'examples/compatibility'])
        compatibility_hash = hashlib.sha256(compatibility_file.read_bytes()).hexdigest()
        run('compatibility-second', [moon, 'run', '--target', 'js', '-j', '1', 'examples/compatibility'])
        if hashlib.sha256(compatibility_file.read_bytes()).hexdigest() != compatibility_hash:
            raise RuntimeError('Compatibility fixture cross-process determinism failed')
        report['compatibility_fixture_determinism'] = {'status': 'PASS', 'sha256': compatibility_hash}
        run('compatibility-regression', [sys.executable, ROOT / 'scripts/verify_compatibility.py', '--report', out / 'compatibility.json'])
        run('reuse', [sys.executable, ROOT / 'scripts/verify_reuse.py', '--moon', moon, '--output', out / 'reuse'])
        report['independent_module_reuse'] = json.loads((out / 'reuse/reuse.json').read_text())
        if report['independent_module_reuse']['status'] != 'PASS': raise RuntimeError('Independent module reuse failed')
        run('guards', [sys.executable, ROOT / 'scripts/verify_guards.py', '--moon', moon,
                       '--candidate-report', out / 'reuse/reuse.json', '--output', out / 'guards'])
        report['fail_closed_guards'] = json.loads((out / 'guards/guards.json').read_text())
        report['status'] = 'PASS'
    except Exception as e:
        report['status'] = 'FAIL'; report['error'] = str(e)
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'acceptance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1

if __name__ == '__main__': sys.exit(main())
