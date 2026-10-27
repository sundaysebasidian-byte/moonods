#!/usr/bin/env python3
"""Bounded source/CLI interoperability checks; no network, installs or publication.

Creates ODS from the repository's synthetic FODS using an existing LibreOffice.
An optional official LibreOffice/core fixture must be supplied by the caller;
its exact pinned hash is checked. Never redistributes that upstream binary.
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from ods_value_oracle import decimal_identity, typed_observation
from prepare_reader_fixtures import (PREFIX, SUFFIX, TEXT, package, semantics,
                                     fixed_producer_xml)

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_SHA = '634fe14c4daaf4e3e15db2dd3b72ba0deabb52d95a05d0f95764006c838ba0dc'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def typed(path):
    return typed_observation(semantics(path))


def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--moon', default='moon')
    p.add_argument('--soffice', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--upstream-fixture', type=Path)
    args = p.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'steps': [], 'scope': 'JS source CLI and independent Python typed/CSV oracle; real headless LibreOffice conversion',
              'not_tested': ['registry installation', 'Excel', 'GUI/layout',
                             'general formula recalculation', 'concurrency/crash']}
    def run(label, command, env=None, expected=0):
        step = {'name': label, 'command': [str(c) for c in command],
                'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'exit_code': None, 'expected_exit_code': expected}
        if env is not None:
            # Only task-specific ODS options; never persist ambient credentials.
            step['environment_overrides'] = {
                k: v for k, v in env.items() if k.startswith('ODS_')}
        report['steps'].append(step)
        try:
            r = subprocess.run(step['command'], cwd=ROOT, env=env,
                               capture_output=True, text=True, timeout=120)
        except (subprocess.TimeoutExpired, OSError) as exc:
            step['execution_error'] = type(exc).__name__
            step['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            raise
        step['exit_code'] = r.returncode
        step['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out/(label+'.stdout.txt')).write_text(r.stdout)
        (out/(label+'.stderr.txt')).write_text(r.stderr)
        require(r.returncode == expected, label+' unexpected exit status')
        return r.stdout
    def cli(label, source, *, csv_export=False, accept=True, expected=0, edit=None):
        ods = out/(label+'.ods')
        csv_file = out/(label+'.csv')
        # Failed import must leave both pre-existing outputs and input intact.
        if expected:
            ods.write_bytes(b'old ODS output')
            csv_file.write_bytes(b'old CSV output')
        before = sha(source)
        env = {k: v for k, v in os.environ.items() if not k.startswith('ODS_')}
        env.update(ODS_INPUT=str(source), ODS_OUTPUT=str(ods),
                   ODS_ACCEPT_LOSS='1' if accept else '')
        if edit is not None:
            env['ODS_SET'] = edit
        if csv_export:
            env['ODS_CSV'] = str(csv_file)
        try:
            log = run(label, ['node', tool], env, expected)
        finally:
            after = sha(source)
            report['steps'][-1]['input'] = {
                'path': str(source), 'sha256_before': before,
                'sha256_after': after, 'unchanged': after == before}
        require(after == before, label+' mutated input')
        if expected:
            require(ods.read_bytes() == b'old ODS output', label+' changed old ODS')
            require(csv_file.read_bytes() == b'old CSV output', label+' changed old CSV')
            require(not list(out.glob('.moonods-*.tmp')), label+' left staging files')
        else:
            require(ods.is_file(), label+' missing output')
        return ods, csv_file, log
    def convert(label, source):
        dest = out/(label+'-saved')
        dest.mkdir()
        with tempfile.TemporaryDirectory(prefix='moonods-office-') as profile:
            run(label, [args.soffice, '-env:UserInstallation='+Path(profile).as_uri(),
                        '--headless', '--nologo', '--nodefault', '--norestore',
                        '--convert-to', 'ods:calc8', '--outdir', dest, source])
        saved = dest/(source.stem+'.ods')
        require(saved.is_file(), label+' did not produce ODS')
        return saved
    try:
        report['moon'] = run('version', [args.moon, 'version', '--all'])
        report['node'] = run('node-version', ['node', '--version']).strip()
        report['office'] = run('office-version', [args.soffice, '--version']).strip()
        run('build', [args.moon, 'build', '--target', 'js', '-j', '1', '--deny-warn', 'examples/ods_tool'])
        tool = ROOT/'_build/js/debug/build/examples/ods_tool/ods_tool.js'
        # Workspace builds include module path in their target directory.
        if not tool.is_file():
            tool = ROOT/'_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js'
        require(tool.is_file(), 'CLI artifact missing')
        synthetic = ROOT/'tests/reader-fixtures/source/rich-text.fods'
        before_synthetic = sha(synthetic)
        direct = out/'synthetic-direct.ods'
        xml = synthetic.read_text().replace('<!-- Synthetic MoonODS test input, MIT. No real procurement/customer data. -->', '').replace('<office:document ', '<office:document-content ').replace('</office:document>', '</office:document-content>').replace(' office:mimetype="application/vnd.oasis.opendocument.spreadsheet"', '')
        direct.write_bytes(package(xml.encode()))
        direct_out, direct_csv, _ = cli('direct-rich-import', direct, csv_export=True)
        with direct_csv.open(newline='', encoding='utf-8') as stream:
            require(list(csv.reader(stream)) == [['采购 中文  \t\n尾', '12345']],
                    'direct synthetic CSV whitespace/type oracle mismatch')
        require(typed(direct_out) == typed(direct), 'direct rich text changed')
        rich = convert('synthetic-office', synthetic)
        require(sha(synthetic) == before_synthetic, 'synthetic source mutated')
        require(bool(fixed_producer_xml(rich).findall('.//{'+TEXT+'}span')),
                'LibreOffice output has no span; test would not cover the new feature')
        first, csv_file, log = cli('rich-import', rich, csv_export=True)
        require('RICH_TEXT_FORMATTING_DROPPED sheet=Rich row=0 col=0' in log,
                'missing positioned rich-text loss notice')
        with csv_file.open(newline='', encoding='utf-8') as stream:
            require(list(csv.reader(stream)) == [['采购 中文  尾', '12345']],
                    'LibreOffice-produced CSV whitespace/type oracle mismatch')
        expected = typed(rich)
        require(typed(first) == expected, 'rich import changed typed values/text')
        second, _, _ = cli('rich-reread', first)
        require(typed(second) == expected, 'rich export reread changed data')
        cli('rich-no-opt-in', rich, csv_export=True, accept=False, expected=1)
        saved = convert('moonods-office', first)
        require(typed(saved) == expected, 'office resave changed typed rich data')
        final, _, _ = cli('office-reread', saved)
        require(typed(final) == expected, 'office output reread mismatch')
        report['synthetic'] = {'source': str(synthetic.relative_to(ROOT)),
                               'source_sha256': before_synthetic, 'ods_sha256': sha(rich),
                               'producer_normalization': 'This LibreOffice FODS conversion removes the source tab and line-break. Direct synthetic ODS retains them; MoonODS is checked against each actual input, not against a claimed lossless office conversion.',
                               'provenance': 'MIT synthetic FODS; output produced by reported LibreOffice, not an official LibreOffice corpus fixture'}
        for i, inner in enumerate(['<x:span><x:a>link</x:a></x:span>',
                                    '<x:span><o:scripts/></x:span>',
                                    '<x:span x:unknown="1">bad</x:span>']):
            bad = out/('unsupported-'+str(i)+'.ods')
            content = PREFIX+'<t:table-row><t:table-cell o:value-type="string"><x:p>'+inner+'</x:p></t:table-cell></t:table-row>'+SUFFIX
            bad.write_bytes(package(content.encode()))
            _, _, failure_log = cli('reject-'+str(i), bad, csv_export=True, expected=1)
            require("sheet 'Input' row 0 col 0" in failure_log, 'refusal lost cell context')
        fixed = ROOT/'tests/reader-fixtures/external/libreoffice-dev-types.ods'
        fixed_out, fixed_csv, _ = cli('existing-fixed', fixed, csv_export=True, edit='0,1,0,8.5')
        edited_expected = typed(fixed)
        edited_expected['Types']['1,0']['value'] = decimal_identity('8.5')
        require(typed(fixed_out) == edited_expected, 'existing fixed producer typed edit regression')
        with fixed_csv.open(newline='', encoding='utf-8') as stream:
            require(list(csv.reader(stream))[1][0] == '8.5', 'typed edit missing from exported CSV')
        fixed_again, _, _ = cli('existing-fixed-reread', fixed_out)
        require(typed(fixed_again) == edited_expected, 'fixed fixture reread regression')
        fixed_saved = convert('existing-fixed-office', fixed_out)
        require(typed(fixed_saved) == edited_expected, 'fixed typed edit office resave mismatch')
        fixed_final, _, _ = cli('existing-fixed-office-reread', fixed_saved)
        require(typed(fixed_final) == edited_expected, 'fixed office reread mismatch')
        report['existing_fixed_sha256'] = sha(fixed)
        report['existing_fixed_workflow'] = 'actual independent LibreOfficeDev input -> typed Types(1,0) edit 7.5 to8.5 -> CSV/ODS -> independent Python comparison -> stable LibreOffice resave -> library reread; other types, coordinates, merge and formula/cache checked'
        report['official_upstream'] = 'NOT_RUN: --upstream-fixture not supplied'
        if args.upstream_fixture:
            upstream = args.upstream_fixture.resolve()
            require(sha(upstream) == UPSTREAM_SHA, 'official fixed fixture hash mismatch')
            upstream_out, _, _ = cli('official-fixed', upstream)
            sheets = typed(upstream_out)
            cells = next(iter(sheets.values()))
            for key, value in [('1,1', {'value-type':'string', 'text':'LibreOffice Calc'}),
                               ('2,1', {'value-type':'float','value':decimal_identity('12345')}),
                               ('3,1', {'value-type':'string','text':'A < B'}),
                               ('4,1', {'value-type':'float','value':decimal_identity('0')})]:
                require(cells.get(key) == value, 'upstream assertion failed at '+key)
            again, _, _ = cli('official-fixed-reread', upstream_out)
            require(typed(again) == sheets, 'upstream export/reread mismatch')
            report['official_upstream'] = {'sha256': sha(upstream),
                    'source': 'LibreOffice/core@528ba1172ce7f2193db9297a3dac0bc4da7cd9d9/sc/qa/unit/data/ods/basic-cell-content.ods',
                    'status': 'PASS B2-B5 types and values; export/reread'}
        report['status'] = 'PASS'
    except Exception as exc:
        report['status'] = 'FAIL'
        report['error'] = str(exc)
        raise
    finally:
        report['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        (out/'receipt.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
