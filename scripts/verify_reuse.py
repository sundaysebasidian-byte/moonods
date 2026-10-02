#!/usr/bin/env python3
"""Consume moon package output in a separate module; no publication or installs."""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path
from lxml import etree
from odf import teletype
from fetch_schemas import SCHEMAS
from verify_deps import verify
from verify_external import check_package, cell_value

ROOT = Path(__file__).resolve().parent.parent

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def extract(archive, destination):
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            p = Path(info.filename)
            if p.is_absolute() or '..' in p.parts or '\\' in info.filename:
                raise ValueError('Unsafe candidate path')
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Candidate symlink unsupported')
        z.extractall(destination)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--moon', required=True, type=Path)
    ap.add_argument('--output', type=Path, default=ROOT / 'evidence/reuse-review')
    args = ap.parse_args()
    # Resolve in the caller's directory before changing into the extracted
    # consumer. A relative --moon path must keep referring to the same SDK.
    requested_moon_path = str(args.moon)
    args.moon = args.moon.resolve(strict=True)
    out = args.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    steps = []
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'steps': steps,
              'requested_moon_path': requested_moon_path, 'resolved_moon_path': str(args.moon),
              'scope': 'Independent local module consumes extracted moon package candidate via moon.work',
              'mooncakes_published_or_remote_consumption': False,
              'unmeasured': ['office applications', 'fresh machine', 'network package installation', 'market demand']}
    def run(name, argv, cwd):
        r = subprocess.run([str(a) for a in argv], cwd=cwd, env=os.environ.copy(), capture_output=True, text=True, timeout=120)
        (out / (name + '.stdout.txt')).write_text(r.stdout)
        (out / (name + '.stderr.txt')).write_text(r.stderr)
        steps.append({'name': name, 'command': [str(a) for a in argv], 'cwd': str(cwd),
                      'exit_code': r.returncode, 'status': 'PASS' if r.returncode == 0 else 'FAIL'})
        if r.returncode: raise RuntimeError(f'{name} failed; retained logs')
        return r.stdout + r.stderr
    try:
        report['verified_dependencies'] = verify()
        module_version = re.search(r'^version = "([^"]+)"$', (ROOT / 'moon.mod').read_text(), re.M)
        assert module_version, 'Missing candidate version'
        candidate_version = module_version[1]
        report['candidate_version'] = candidate_version
        run('package', [args.moon, 'package', '--frozen', '--list'], ROOT)
        original = ROOT / '_build/publish' / f'sundaysebasidian-byte-moonods-{candidate_version}.zip'
        candidate = out / f'moonods-local-candidate-{candidate_version}.zip'
        shutil.copyfile(original, candidate)
        with zipfile.ZipFile(candidate) as z:
            names = z.namelist()
            assert z.testzip() is None
            assert {'moon.mod', 'moon.pkg', 'cell.mbt', 'workbook.mbt', 'package.mbt', 'LICENSE'} <= set(names)
            assert not any(n.startswith(('evidence/', 'vendor/', 'fixtures/', 'scripts/', '.mooncakes/', '_build/')) for n in names)
            # Exact original source bytes, consumed only from the packaged copy.
            fingerprints = {n: hashlib.sha256(z.read(n)).hexdigest() for n in names if n.endswith('.mbt') or n in ['moon.mod', 'moon.pkg']}
            assert all(digest(ROOT / n) == h for n, h in fingerprints.items())
            # Documentation/licenses/interfaces must describe the same snapshot
            # as the code actually consumed, rather than an earlier candidate.
            all_fingerprints = {n: hashlib.sha256(z.read(n)).hexdigest() for n in names if not n.endswith('/')}
            assert all(digest(ROOT / n) == h for n, h in all_fingerprints.items()), 'Candidate file differs from current checkout'
        report['candidate'] = {'file': candidate.name, 'sha256': digest(candidate), 'bytes': candidate.stat().st_size,
                               'files': names, 'source_sha256': fingerprints,
                               'all_files_sha256': all_fingerprints,
                               'all_candidate_bytes_match_checkout': True}
        fixture = ROOT / 'fixtures/reuse-consumer'
        report['consumer_source_sha256'] = {str(p.relative_to(fixture)): digest(p) for p in sorted(fixture.rglob('*')) if p.is_file() and '_build' not in p.parts}
        # All workspace members are physically extracted archives or copied
        # consumer fixture, never linked to the producer checkout.
        with tempfile.TemporaryDirectory(prefix='moonods-reuse-') as temp:
            work = Path(temp)
            extract(candidate, work / 'candidate')
            shutil.copytree(fixture, work / 'consumer', ignore=shutil.ignore_patterns('_build', '.mooncakes'))
            (work / 'moon.work').write_text('members = [\n  "candidate",\n  "consumer",\n]\n')
            report['workspace_config'] = (work / 'moon.work').read_text()
            consumer = work / 'consumer'
            run('consumer-format', [args.moon, 'fmt', '--check', 'src'], consumer)
            run('consumer-check', [args.moon, 'check', '--target', 'js', '-j', '1', '--deny-warn'], consumer)
            run('consumer-build', [args.moon, 'build', '--target', 'js', '-j', '1', '--deny-warn'], consumer)
            tests = run('consumer-test', [args.moon, 'test', '--target', 'js', '-j', '1', '--deny-warn', 'src'], consumer)
            match = re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)', tests)
            assert match and match[1] == match[2] and match[3] == '0' and int(match[1]) >= 5
            report['tests'] = {'total': int(match[1]), 'passed': int(match[2]), 'failed': int(match[3])}
            run('consumer-first', [args.moon, 'run', '--target', 'js', '-j', '1', 'src'], consumer)
            generated = consumer / 'generated'
            first = {p.name: digest(p) for p in generated.glob('*.ods')}
            assert set(first) == {'business.ods', 'laboratory.ods', 'declarations.ods'}
            run('consumer-second', [args.moon, 'run', '--target', 'js', '-j', '1', 'src'], consumer)
            assert first == {p.name: digest(p) for p in generated.glob('*.ods')}
            sources = {k: ROOT / '.schemas' / (k + '.rng') for k in SCHEMAS}
            assert all(digest(p) == SCHEMAS[k][1] for k, p in sources.items())
            schemas = {k: etree.RelaxNG(etree.parse(str(p))) for k, p in sources.items()}
            count = 0
            def expect(cell, value):
                nonlocal count
                assert cell_value(cell) == value, (cell_value(cell), value)
                count += 1
            b = check_package(generated / 'business.ods', schemas)
            assert list(b) == ['业务汇总']
            g = b['业务汇总']
            expect(g[0][0], ('string', '下游提供的商品清单'))
            assert g[0][0].getAttribute('numbercolumnsspanned') == '3'
            assert all(c.qname[1] == 'covered-table-cell' for c in g[0][1:])
            for c, v in enumerate(['商品', '数量', '金额']): expect(g[1][c], ('string', v))
            for r, values in [(2, [('string', '教学套件 <A>&B'), ('number', 2.0), ('number', 50.0)]),
                              (3, [('string', '耗材'), ('number', 5.0), ('number', 12.5)]),
                              (4, [('string', '合计'), ('number', 7.0), ('number', 62.5)])]:
                for c, value in enumerate(values): expect(g[r][c], value)
            assert g[2][2].getAttribute('stylename') == 'Decimal2'
            l = check_package(generated / 'laboratory.ods', schemas)
            assert list(l) == ['测量', '记录来源']
            note = ' 中文  空白\t制表\n下一行 😀 '
            for r, values in [(1, [('date', '2024-02-29'), ('number', -2.5), ('boolean', True), ('string', note)]),
                              (2, [('date', '2026-10-01'), ('number', 0.0), ('boolean', False), ('string', '')])]:
                for c, value in enumerate(values): expect(l['测量'][r][c], value)
            assert teletype.extractText(l['测量'][1][3]) == note
            expect(l['记录来源'][0][0], ('string', '合成批次 LAB-02'))
            expect(l['记录来源'][1][0], None); expect(l['记录来源'][1][1], ('string', ''))
            d = check_package(generated / 'declarations.ods', schemas)
            assert list(d) == ['调用方缓存']
            g = d['调用方缓存']
            expect(g[0][0], ('number', 1.0)); expect(g[1][0], ('number', 2.0))
            for r, f, value in [
                (0, 'of:=SUM([.A1:.A2])', ('number', 99.0)),
                (1, 'of:=[.A1]<[.A2]', ('boolean', True)),
                (2, 'of:="下游中文 & 缓存"', ('string', '下游中文 & 缓存')),
                (3, 'of:=DATE(2026;10;1)', ('date', '2026-10-01'))]:
                assert g[r][1].getAttribute('formula') == f
                expect(g[r][1], value)
            report['independent_reader'] = {'status': 'PASS', 'typed_cell_assertions': count,
                                            'official_rng_xml_count': 9, 'package_checks': 'PASS',
                                            'inconsistent_cache_preserved': 99, 'calculation_performed': False}
            report['cross_process_determinism'] = {'status': 'PASS', 'sha256': first}
            for p in generated.glob('*.ods'): shutil.copyfile(p, out / p.name)
        report['status'] = 'PASS'
    except Exception as error:
        report['status'] = 'FAIL'; report['error'] = str(error)
    report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'reuse.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1

if __name__ == '__main__': sys.exit(main())
