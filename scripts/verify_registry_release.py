#!/usr/bin/env python3
"""Verify released 0.2.0 from an empty registry; no publishing or credentials.

verify_registry.py remains frozen to historical 0.1.0.
"""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess
from pathlib import Path
from verify_consumer_outputs import verify_generated
from verify_wasm_output import decode_output

ROOT = Path(__file__).resolve().parent.parent

def hashes(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--sdk',required=True,type=Path)
    ap.add_argument('--candidate-report',required=True,type=Path)
    ap.add_argument('--output',required=True,type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    work=out/'isolated-work'
    if work.exists():raise SystemExit('Use a new output directory: registry/package cache must start empty')
    work.mkdir();home=work/'sdk-home';home.mkdir()
    for name in ['bin','lib','include']:(home/name).symlink_to(args.sdk.resolve()/name)
    (home/'registry').mkdir()
    consumer=work/'consumer'
    shutil.copytree(ROOT/'fixtures/reuse-consumer',consumer,ignore=shutil.ignore_patterns('_build','.mooncakes'))
    env=os.environ.copy();env['MOON_HOME']=str(home);env['RUST_LOG']='error'
    moon=home/'bin/moon';steps=[]
    report={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'steps':steps,
        'scope':'Formal registry 0.2.0 install; initially empty index/package cache; JS and Wasm GC consumers',
        'initial_registry_entries':[],'credentials_copied':False,'local_workspace':False,
        'existing_sdk_core_reused':True,'not_measured':['fresh machine','Office apps','native/llvm/wasm backends']}
    def run(name,argv):
        p=subprocess.run([str(x) for x in argv],cwd=consumer,env=env,capture_output=True,text=True,timeout=180)
        (out/(name+'.stdout.txt')).write_text(p.stdout);(out/(name+'.stderr.txt')).write_text(p.stderr)
        steps.append({'name':name,'command':[str(x) for x in argv],'exit_code':p.returncode})
        if p.returncode:raise RuntimeError(name+' failed; retained logs')
        return p.stdout+p.stderr
    try:
        expected=json.loads(args.candidate_report.read_text())['candidate']['all_files_sha256']
        mod=(ROOT/'moon.mod').read_bytes()
        assert expected['moon.mod']==hashlib.sha256(mod).hexdigest(),'Candidate manifest differs from source'
        assert re.search(rb'^version = "0\.2\.0"$',mod,re.M),'This verifier is for 0.2.0'
        assert not list((home/'registry').iterdir()) and not (consumer/'.mooncakes').exists()
        assert not (consumer/'moon.work').exists()
        run('registry-update',[moon,'update'])
        run('consumer-format',[moon,'fmt','--check','src'])
        run('js-check',[moon,'check','--target','js','-j','1','--deny-warn'])
        actual=hashes(consumer/'.mooncakes/sundaysebasidian-byte/moonods')
        assert actual==expected,'Registry bytes differ from CI-verified publish candidate'
        report['published_package']={'module':'sundaysebasidian-byte/moonods','version':'0.2.0',
            'file_count':len(actual),'all_files_sha256':actual,'all_registry_bytes_match_publish_candidate':True}
        report['backend_tests']={}
        for target in ['js','wasm-gc']:
            if target!='js':run(target+'-check',[moon,'check','--target',target,'-j','1','--deny-warn'])
            run(target+'-build',[moon,'build','--target',target,'-j','1','--deny-warn'])
            text=run(target+'-test',[moon,'test','--target',target,'-j','1','--no-parallelize','--deny-warn','src'])
            m=re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)',text)
            assert m and m[1]==m[2] and m[3]=='0' and int(m[1])>=5
            report['backend_tests'][target]={'total':int(m[1]),'passed':int(m[2]),'failed':int(m[3])}
        generated=consumer/'generated'
        run('js-first',[moon,'run','--target','js','-j','1','src']);first=hashes(generated)
        run('js-second',[moon,'run','--target','js','-j','1','src']);assert hashes(generated)==first
        report['js_reader']=verify_generated(generated,ROOT/'.schemas')
        wasm_dir=work/'wasm-generated'
        wf=decode_output(run('wasm-first',[moon,'run','--target','wasm-gc','-j','1','src']),wasm_dir)
        ws=decode_output(run('wasm-second',[moon,'run','--target','wasm-gc','-j','1','src']),wasm_dir)
        assert wf==ws==first,'Consumer ODS bytes differ across processes or backends'
        report['wasm_reader']=verify_generated(wasm_dir,ROOT/'.schemas')
        report['cross_process_and_backend_bytes']={'status':'PASS','sha256':first}
        for directory,name in [(generated,'js'),(wasm_dir,'wasm-gc')]:
            (out/name).mkdir(exist_ok=True)
            for p in directory.glob('*.ods'):shutil.copyfile(p,out/name/p.name)
        report['status']='PASS'
    except Exception as e:report.update(status='FAIL',error=str(e))
    report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out/'registry.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return 0 if report['status']=='PASS' else 1

if __name__=='__main__':raise SystemExit(main())
