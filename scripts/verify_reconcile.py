#!/usr/bin/env python3
"""Independent business oracle for an actual ZIP and existing native Office."""
if not __debug__:
    raise SystemExit('verification requires assertions; Python optimization is unsupported')

import argparse
import copy
import csv
import hashlib
import json
import os
import re
from pathlib import Path
import signal
import subprocess
import time
import datetime
import zipfile
import sys
from lxml import etree as ET
from verify_delivery_consumer import unpack
from verify_value import semantic
from ods_value_oracle import normalize_expected, expected_number
from source_manifest import verify_source_manifest


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', required=True, type=Path)
    p.add_argument('--sdk', required=True, type=Path)
    p.add_argument('--soffice', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    out = a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    root = out/'MoonODS'; archive = a.archive.resolve(); sdk = a.sdk.resolve()
    unpack(archive, root, 'MoonODS/')
    state = verify_source_manifest(root)
    env = {k:v for k,v in os.environ.items() if not k.startswith(('MOON_', 'REPORT_', 'RECONCILE_', 'ODS_'))}
    env.update(MOON_HOME=str(out/'moon-state'), MOON_TOOLCHAIN_ROOT=str(sdk), PATH=str(sdk/'bin')+':'+os.environ['PATH'])
    report = {'status':'RUNNING','source_commit':state['head'],'archive_sha256':sha(archive),'scope':'synthetic but input-driven procurement correction; actual ZIP, public API, independent integer-cent/XML/CSV oracle, real headless Office; no competitor execution or registry install','steps':[],'negative_cases':[]}

    def run(name, cmd, extra=None, expected=0, reason=None):
        utc = datetime.datetime.now(datetime.timezone.utc).isoformat(); start = time.monotonic()
        proc = subprocess.Popen([str(x) for x in cmd], cwd=root, env={**env,**(extra or {})}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        timed = False
        try: stdout,stderr = proc.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            timed = True; os.killpg(proc.pid, signal.SIGTERM)
            try: stdout,stderr = proc.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL); stdout,stderr = proc.communicate()
        (out/(name+'.stdout.txt')).write_bytes(stdout); (out/(name+'.stderr.txt')).write_bytes(stderr)
        reason_match = reason is None or reason in (stdout+stderr).decode(errors='replace')
        report['steps'].append({'name':name,'command':[str(x) for x in cmd],'environment_overrides':extra or {},'started_utc':utc,'elapsed_seconds':round(time.monotonic()-start,3),'exit_code':proc.returncode,'expected_exit':expected,'expected_reason':reason,'reason_match':reason_match,'timed_out':timed})
        if timed or proc.returncode != expected: raise RuntimeError(name+' unexpected result')
        if not reason_match: raise RuntimeError(name+' did not reach the expected refusal reason')
        return stdout.decode(errors='replace')

    def rows(path):
        with path.open(newline='') as f: return list(csv.reader(f,strict=True))

    def mutate(source, dest, which):
        ns={'t':'urn:oasis:names:tc:opendocument:xmlns:table:1.0','o':'urn:oasis:names:tc:opendocument:xmlns:office:1.0','x':'urn:oasis:names:tc:opendocument:xmlns:text:1.0'}
        with zipfile.ZipFile(source) as zin:
            xml=ET.fromstring(zin.read('content.xml'),ET.XMLParser(resolve_entities=False,no_network=True,load_dtd=False)); table=xml.findall('.//t:table',ns)[0]
            if xml.nsmap.get('of') != 'urn:oasis:names:tc:opendocument:xmlns:of:1.2': raise ValueError('fixture formula namespace missing')
            cell=table.findall('t:table-row',ns)[2 if which=='stale-cache' else 1].findall('t:table-cell',ns)[5 if which in ('formula','stale-cache') else 4 if which=='overflow' else 8]
            if which=='formula': cell.set('{'+ns['t']+'}formula','of:=WEBSERVICE("https://example.invalid")')
            elif which=='overflow': cell.set('{'+ns['o']+'}value','20000000')
            elif which=='stale-cache': cell.set('{'+ns['o']+'}value','1')
            elif which=='note':
                cell.clear(); cell.set('{'+ns['o']+'}value-type','string'); ET.SubElement(cell,'{'+ns['x']+'}p').text=' =1+2'
            with zipfile.ZipFile(dest,'w') as zout:
                for info in zin.infolist(): zout.writestr(info,ET.tostring(xml,encoding='utf-8',xml_declaration=True) if info.filename=='content.xml' else zin.read(info))

    try:
        run('optimized-driver-refused',[sys.executable,'-O','scripts/verify_reconcile.py'],expected=1,reason='verification requires assertions; Python optimization is unsupported')
        run('optimized-environment-refused',[sys.executable,'scripts/verify_reconcile.py'],{'PYTHONOPTIMIZE':'1'},expected=1,reason='verification requires assertions; Python optimization is unsupported')
        report['toolchain']=run('versions',['moon','version','--all'])
        run('restore-declared-dependency',['python3','scripts/restore_deps.py'])
        run('workspace',['moon','work','use','.mooncakes/moonbit-community/flate'])
        unit=run('project-js-regression',['moon','test','--frozen','--target','js','--deny-warn','-j','1','--no-parallelize','-p','sundaysebasidian-byte/moonods','-p','sundaysebasidian-byte/moonods/tests/consumer'])
        summaries = re.findall(r'^Total tests: (\d+), passed: (\d+), failed: (\d+)\.$', unit, re.M)
        if len(summaries) != 1: raise ValueError('missing or ambiguous project regression summary')
        total, passed, failed = map(int, summaries[0])
        if total < 76 or total != passed or failed != 0: raise ValueError('project regression incomplete or failed')
        report['project_js_tests'] = total
        generated=out/'generated'; generated.mkdir()
        run('generate-template',['moon','run','--frozen','--target','js','--deny-warn','-j','1','examples/procurement'],{'REPORT_OUTPUT':str(generated)})
        report['office_version']=run('office-version',[a.soffice.resolve(),'--version']).strip()
        office=out/'office-input'; office.mkdir()
        run('office-supplier-input',[a.soffice.resolve(),'-env:UserInstallation='+(out/'profile-in').as_uri(),'--headless','--nologo','--nodefault','--norestore','--convert-to','ods:calc8','--outdir',office,generated/'procurement.ods'])
        source=office/'procurement.ods'; source_before=sha(source)
        before=semantic(source)
        changes=out/'changes.csv'; changes.write_text('订单,数量\r\nSYN-202610-001,5\r\nSYN-202610-004,0\r\n',newline='')
        cmd=['moon','run','--frozen','--target','js','--deny-warn','-j','1','examples/reconcile']
        result=out/'corrected'; result.mkdir()
        conf={'RECONCILE_INPUT':str(source),'RECONCILE_CHANGES':str(changes),'RECONCILE_OUTPUT':str(result),'RECONCILE_ACCEPT_LOSS':'1'}
        marker=run('apply-business-corrections',cmd,conf)
        if 'total_cents=100650 changed_orders=2 over_budget_departments=1' not in marker: raise ValueError('business outcome marker differs')
        expected=copy.deepcopy(before)
        d=expected['采购明细']; d['1,3']['value']=5.0; d['1,5']['value']=627.5; d['4,3']['value']=0.0; d['4,5']['value']=0.0
        b=expected['预算复核']; b['0,4']={'value-type':'string','text':'超预算'}; b['1,2']['value']=787.5; b['1,3']['value']=-187.5; b['2,2']['value']=219.0; b['2,3']['value']=81.0; b['1,4']={'value-type':'boolean','boolean-value':'true'}; b['2,4']={'value-type':'boolean','boolean-value':'false'}
        expected=normalize_expected(expected)
        assert semantic(result/'reconciled.ods')==expected
        detail=rows(result/'details.csv'); assert detail[1][3:6]==['5','125.5','627.5'] and detail[4][3:6]==['0','9.5','0']
        assert detail[1][8]=='含引号"样品",\n第二行' and detail[2][8]==detail[3][8]==''
        assert rows(result/'audit.csv')==[['订单','旧数量','新数量','旧小计缓存','新小计缓存'],['SYN-202610-001','3','5','376.5','627.5'],['SYN-202610-004','5','0','47.5','0']]
        # CSV ordering does not determine spreadsheet/audit ordering.
        reverse=out/'reverse.csv'; reverse.write_text('订单,数量\r\nSYN-202610-004,0\r\nSYN-202610-001,5\r\n',newline='')
        repeated=out/'repeat'; repeated.mkdir()
        run('order-independent-repeat',cmd,{**conf,'RECONCILE_CHANGES':str(reverse),'RECONCILE_OUTPUT':str(repeated)})
        assert all((repeated/n).read_bytes()==(result/n).read_bytes() for n in ['reconciled.ods','details.csv','audit.csv'])
        returned=out/'office-return'; returned.mkdir()
        run('office-open-save-corrected',[a.soffice.resolve(),'-env:UserInstallation='+(out/'profile-out').as_uri(),'--headless','--nologo','--nodefault','--norestore','--convert-to','ods:calc8','--outdir',returned,result/'reconciled.ods'])
        assert semantic(returned/'reconciled.ods')==expected
        no_changes=out/'no-changes.csv'; no_changes.write_text('订单,数量\r\n',newline='')
        roundtrip=out/'office-readback'; roundtrip.mkdir()
        run('same-candidate-return-readback',cmd,{**conf,'RECONCILE_INPUT':str(returned/'reconciled.ods'),'RECONCILE_CHANGES':str(no_changes),'RECONCILE_OUTPUT':str(roundtrip)})
        assert semantic(roundtrip/'reconciled.ods')==expected
        assert rows(roundtrip/'audit.csv')==[rows(result/'audit.csv')[0]]
        # A namespace-preserving no-op rewrite is a positive control for the
        # same mutation mechanism used by the business-specific refusals.
        control=out/'valid-rewrite.ods'; mutate(source,control,'rewrite-control')
        control_out=out/'rewrite-control'; control_out.mkdir()
        control_marker=run('valid-mutation-control',cmd,{**conf,'RECONCILE_INPUT':str(control),'RECONCILE_CHANGES':str(no_changes),'RECONCILE_OUTPUT':str(control_out)})
        assert 'total_cents=80300 changed_orders=0' in control_marker
        assert rows(control_out/'audit.csv')==[rows(result/'audit.csv')[0]]
        stale=out/'stale-cache.ods'; mutate(source,stale,'stale-cache')
        stale_out=out/'stale-cache-repaired'; stale_out.mkdir()
        stale_marker=run('unrequested-stale-cache-is-audited',cmd,{**conf,'RECONCILE_INPUT':str(stale),'RECONCILE_CHANGES':str(no_changes),'RECONCILE_OUTPUT':str(stale_out)})
        assert 'changed_orders=0' in stale_marker and 'audited_orders=1' in stale_marker
        assert rows(stale_out/'audit.csv')==[rows(result/'audit.csv')[0],['SYN-202610-002','12','12','1','219']]
        assert semantic(stale_out/'reconciled.ods')['采购明细']['2,5']['value']==expected_number(219.0)
        noop=out/'noop.csv'; noop.write_text('订单,数量\r\nSYN-202610-001,3\r\n',newline='')
        noop_out=out/'noop-request'; noop_out.mkdir()
        noop_marker=run('noop-request-counter',cmd,{**conf,'RECONCILE_CHANGES':str(noop),'RECONCILE_OUTPUT':str(noop_out)})
        assert 'changed_orders=0' in noop_marker and 'requested_orders=1' in noop_marker
        cases=[('unknown-order','订单,数量\r\nmissing,2\r\n',None),('duplicate-order','订单,数量\r\nSYN-202610-001,2\r\nSYN-202610-001,3\r\n',None),('fractional-quantity','订单,数量\r\nSYN-202610-001,1.5\r\n',None),('quantity-bound','订单,数量\r\nSYN-202610-001,10001\r\n',None),('wrong-headers','订单,金额\r\n',None),('untrusted-formula',None,'formula'),('money-overflow',None,'overflow'),('formula-like-csv-text',None,'note'),('loss-opt-in-required',None,None),('input-output-alias',None,None),('output-directory',None,None),('malformed-zip',None,None),('oversized-ods',None,None),('oversized-csv',None,None),('invalid-utf8-csv',None,None)]
        for name,csv_text,mutation in cases:
            case=out/name; case.mkdir(); inp=case/'input.ods'; inp.write_bytes(source.read_bytes())
            delta=case/'changes.csv'; delta.write_text(csv_text or changes.read_text(),newline='')
            if mutation: mutate(source,inp,mutation)
            if name=='malformed-zip': inp.write_bytes(b'not a ZIP')
            if name=='oversized-ods':
                with inp.open('wb') as f: f.truncate(33554433)
            if name=='oversized-csv':
                with delta.open('wb') as f: f.truncate(8388609)
            if name=='invalid-utf8-csv': delta.write_bytes(b'\xff')
            for n in ['reconciled.ods','details.csv','audit.csv']: (case/n).write_bytes(b'old-output\n')
            if name=='input-output-alias': inp=case/'reconciled.ods'; inp.write_bytes(source.read_bytes())
            if name=='output-directory': (case/'details.csv').unlink(); (case/'details.csv').mkdir()
            snapshots={p:sha(p) for p in case.iterdir() if p.is_file()}
            config={**conf,'RECONCILE_INPUT':str(inp),'RECONCILE_CHANGES':str(delta),'RECONCILE_OUTPUT':str(case)}
            if name=='loss-opt-in-required': config['RECONCILE_ACCEPT_LOSS']='0'
            reasons={'unknown-order':'unknown amendment order','duplicate-order':'duplicate amendment order','fractional-quantity':'amendment quantity must be decimal digits','quantity-bound':'amendment quantity must be decimal digits','wrong-headers':'missing or unexpected business header','untrusted-formula':'untrusted or unsupported template formula','money-overflow':'line amount exceeds cents budget','formula-like-csv-text':'CSV formula-like text at row','loss-opt-in-required':'data-only import requires allow_formatting_loss=true','input-output-alias':'inputs and outputs must be distinct','output-directory':'output must be a regular file','malformed-zip':'invalid ODS ZIP input size','oversized-ods':'input must be a regular file within the byte budget','oversized-csv':'input must be a regular file within the byte budget','invalid-utf8-csv':'encoded data was not valid'}
            run('reject-'+name,cmd,config,expected=1,reason=reasons[name])
            assert all(sha(p)==h for p,h in snapshots.items())
            assert not list(case.glob('.moonods-*.tmp'))
            report['negative_cases'].append({'name':name,'status':'PASS','expected_refusal_reason':reasons[name],'inputs_and_existing_outputs_unchanged':True})
        assert sha(source)==source_before and sha(archive)==report['archive_sha256']
        report.update(status='PASS',business_outcome={'old_total_cents':80300,'new_total_cents':100650,'changed_orders':2,'over_budget_departments':1,'research_department_remaining_cents':-18750,'operations_remaining_cents':8100},independent_semantic_and_csv_oracles='PASS',order_independent_generation='PASS',actual_Office_input_and_output_roundtrip='PASS',loss_scope='data-only import; no style preservation or GUI proof',formula_scope='recompute only whitelisted template arithmetic in integer cents; not general formula evaluation',input_ods_and_archive_unchanged=True,not_run=['competitor execution/performance','Excel','GUI/print/layout','Wasm/WasmGC/native runtime','registry install or publish'],output_sha256={n:sha(result/n) for n in ['reconciled.ods','details.csv','audit.csv']})
        (out/'expected-semantics.json').write_text(json.dumps(expected,ensure_ascii=False,indent=2)+'\n')
    except Exception as error:
        report.update(status='FAIL',error=type(error).__name__+': '+str(error))
    (out/'reconcile.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return 0 if report['status']=='PASS' else 1


if __name__=='__main__': raise SystemExit(main())
