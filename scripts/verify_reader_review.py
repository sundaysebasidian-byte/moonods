#!/usr/bin/env python3
"""Candidate reader checks, also invoked by the locked acceptance runner.
Needs an installed SDK and pinned dependencies. The Mooncakes resolver may
download missing packages. No SDK install, remote mutation or publication.
"""
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=ROOT/'evidence/typed-reader-20261015')
    parser.add_argument('--soffice')
    args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    report={'scope':'unreleased bounded reader candidate','steps':[],'original_acceptance':'SEPARATE_RUN_REQUIRED','published':False}
    def run(label,args):
        r=subprocess.run(args,cwd=ROOT,capture_output=True,text=True,timeout=180)
        (out/(label+'.log')).write_text(r.stdout+r.stderr)
        report['steps'].append({'name':label,'exit_code':r.returncode,'command':args})
        if r.returncode:raise RuntimeError(label+' failed')
        return r.stdout.strip()
    try:
        report['moon']=run('moon-version',['moon','version'])
        report['moonc']=run('moonc-version',['moonc','-v'])
        report['node']=run('node-version',['node','--version'])
        run('dependencies',[sys.executable,'scripts/verify_deps.py'])
        literals=(ROOT/'reader_zip_wbtest.mbt').read_text()
        manifest=json.loads((ROOT/'tests/reader-fixtures/controls-manifest.json').read_text())
        fixture_results={}
        for name,item in manifest.items():
            raw=(ROOT/'tests/reader-fixtures/controls'/name).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=item['sha256']:
                raise RuntimeError(name+' fixture hash mismatch')
            pattern=r'"'+re.escape(name[:-4])+r'"\s*\|\s*"'+re.escape(name)+r'"\s*=>\s*\[([\d,\s]+)\]'
            match=re.search(pattern,literals)
            if not match: raise RuntimeError(name+' missing embedded fixture')
            embedded=bytes(int(n) for n in re.findall(r'\d+',match[1]))
            if embedded!=raw: raise RuntimeError(name+' embedded byte mismatch')
            fixture_results[name]={'sha256':item['sha256'],'embedded_bytes_match':True,'expected_result':item['expected_moonods_result']}
        match=re.search(r'let zip_libreoffice_fixture : Bytes = \[([\d,\s]+)\]',literals)
        if not match or bytes(int(n) for n in re.findall(r'\d+',match[1]))!=(ROOT/'tests/reader-fixtures/external/libreoffice-dev-types.ods').read_bytes():
            raise RuntimeError('external producer embedded byte mismatch')
        report['fixture_bindings']=fixture_results

        for target in ['js','wasm-gc']:
            run('check-'+target,['moon','check','--target',target,'.'])
            run('build-'+target,['moon','build','--target',target,'.'])
            run('core-tests-'+target,['moon','test','--target',target,'-p','sundaysebasidian-byte/moonods'])
            run('all-workspace-tests-'+target,['moon','test','--target',target])
        command=[sys.executable,'scripts/verify_typed_reader.py','--output',str(out)]
        if args.soffice:command+=['--soffice',args.soffice]
        run('public-consumer',command)
        files=list(ROOT.glob('*.mbt'))+list(ROOT.glob('*.mbti'))+[ROOT/'moon.mod',ROOT/'moon.pkg',ROOT/'moon.work']+list((ROOT/'fixtures/typed-reader-consumer').rglob('*.mbt'))+list((ROOT/'scripts').glob('*reader*.py'))
        report['source_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
        report['result']='PASS_CURRENT_REVIEW_CHECKS_NOT_FULL_RELEASE_ACCEPTANCE'
    except Exception as exc:
        report['result']='FAIL';report['error']=str(exc)
    (out/'review-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if report['result']=='FAIL':raise SystemExit(1)
if __name__=='__main__':main()
