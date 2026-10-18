#!/usr/bin/env python3
"""Run isolated public API consumer, then independently inspect real ODS output.
Uses local source + bundled dependencies, never registry/push/publication.
This is ODS roundtrip validation, not mbtexcel/XLSX interoperability.
"""
import argparse, hashlib, json, os, shutil, subprocess, tempfile, zipfile
from pathlib import Path
from prepare_reader_fixtures import semantics
ROOT = Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--soffice',help='Optional existing LibreOffice executable; no installation')
    args=parser.parse_args()
    evidence = ROOT / 'evidence' / 'typed-reader-20261015'
    evidence.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='moonods-reader-') as tmp:
        work = Path(tmp)
        candidate = work / 'candidate'
        shutil.copytree(ROOT,candidate,ignore=shutil.ignore_patterns('.git','.mooncakes','_build','moon.work','evidence','__pycache__'))
        shutil.copytree(ROOT/'fixtures/typed-reader-consumer',work/'consumer')
        for name in ['zipc-0.2.2','flate-0.2.0']:
            with zipfile.ZipFile(ROOT/'vendor'/f'{name}.zip') as z: z.extractall(work/name.split('-')[0])
        (work/'moon.work').write_text('members = ["candidate", "consumer", "zipc", "flate"]\n')
        source = ROOT/'tests/reader-fixtures/external/libreoffice-dev-types.ods'
        output = evidence/'edited-libreoffice.ods'
        env = dict(os.environ,ODS_INPUT=str(source),ODS_OUTPUT=str(output))
        proc = subprocess.run(['moon','run','--target','js','consumer/src'],cwd=work,env=env,text=True,capture_output=True)
        (evidence/'public-consumer.log').write_text(proc.stdout+proc.stderr)
        if proc.returncode: raise SystemExit('public consumer failed; see log')
        before, after = semantics(source), semantics(output)
        expected = json.loads(json.dumps(before))
        expected['sheets']['Types']['1,0']['value']='8.5'
        expected['sheets']['Types']['1,0']['text']='8.5'
        # Compare typed values and structure, not display strings or producer styles.
        fields = ['value-type','value','boolean-value','date-value','formula','number-columns-spanned','number-rows-spanned','covered']
        def semantic(x):
            result={}
            for sheet,cells in x['sheets'].items():
                result[sheet]={}
                for key,cell in cells.items():
                    record={k:cell[k] for k in fields if k in cell}
                    if cell.get('value-type')=='string': record['text']=cell['text']
                    if record.get('value-type')=='float': record['value']=float(record['value'])
                    result[sheet][key]=record
            return result
        if semantic(after)!=semantic(expected):
            raise RuntimeError('public consumer changed unexpected typed data or missed the requested edit')
        report={'result':'PASS','scope':'isolated MoonBit public consumer + independent Python ODS typed semantic comparison','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'edit':'Types row1 col0: 7.5 -> 8.5','preserved':'other typed data, empty string distinction, whitespace, repeats, 2x2 merge and covered cells, formula and cache','mbtexcel':'NOT_RUN','stable_libreoffice':'NOT_RUN'}
        if args.soffice:
            version=subprocess.run([args.soffice,'--version'],capture_output=True,text=True,check=True).stdout.strip()
            destination=evidence/'libreoffice-dev-resaved'; destination.mkdir(exist_ok=True)
            # Fresh destination avoids any overwrite interaction.
            destination=Path(tempfile.mkdtemp(prefix='office-output-',dir=evidence))
            profile=work/'office-profile'
            app=subprocess.run([args.soffice,'-env:UserInstallation='+profile.as_uri(),'--headless','--nologo','--nodefault','--norestore','--convert-to','ods:calc8','--outdir',str(destination),str(output)],capture_output=True,text=True,timeout=120)
            (evidence/'dev-resave.log').write_text(app.stdout+app.stderr)
            saved=destination/output.name
            if app.returncode!=0 or not saved.is_file(): raise RuntimeError('LibreOffice save failed')
            observed=semantics(saved)
            if semantic(observed)!=semantic(after): raise RuntimeError('application changed typed data')
            report['application_resave']={'result':'PASS','version':version,'scope':'headless native ODS save, independent typed comparison; not GUI','sha256':hashlib.sha256(saved.read_bytes()).hexdigest(),'output':str(saved.relative_to(ROOT))}
            report['stable_libreoffice']='NOT_RUN' if 'Dev' in version or 'alpha' in version else version
            (evidence/'application-resave.json').write_text(json.dumps(report['application_resave'],indent=2)+'\n')
            (evidence/'dev-resave-semantics.json').write_text(json.dumps(observed,indent=2,ensure_ascii=False)+'\n')
        (evidence/'public-consumer.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
if __name__=='__main__': main()
