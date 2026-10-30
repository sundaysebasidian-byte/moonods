#!/usr/bin/env python3
"""Independent property-level checks for the conservative formatting subset.
Synthetic package inputs only; no Office, downloads, installation or publishing.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile
from lxml import etree as E
from prepare_reader_fixtures import package, PREFIX, SUFFIX, ordered_rows, ordered_columns, NS, TABLE, OFFICE
from verify_reader_compat import typed

ROOT=Path(__file__).resolve().parents[1]
STYLE='urn:oasis:names:tc:opendocument:xmlns:style:1.0'
NUMBER='urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0'
FO='urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
DEFS='''<style:default-style style:family="table-cell"/>
<style:style style:name="Parent" style:family="table-cell"><style:table-cell-properties fo:background-color="#FFF2CC" fo:wrap-option="wrap"/></style:style>
<style:style style:name="Header" style:family="table-cell" style:parent-style-name="Parent"/>
<style:style style:name="ActualHeader" style:family="table-cell"><style:table-cell-properties fo:background-color="#17324D" fo:wrap-option="wrap"/><style:text-properties fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold" fo:color="#FFFFFF"/></style:style>
<number:number-style style:name="RenamedNumber"><number:number number:decimal-places="2" number:min-integer-digits="1"/></number:number-style>
<style:style style:name="RenamedCell" style:family="table-cell" style:data-style-name="RenamedNumber"><style:paragraph-properties fo:text-align="end"/></style:style>
<style:style style:name="Unknown" style:family="table-cell"><style:table-cell-properties fo:background-color="#FF0000"/></style:style>'''


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def require(ok,message):
    if not ok:raise RuntimeError(message)

def fixture(path,body,defs=DEFS):
    content=(PREFIX.replace('xmlns:x=', 'xmlns:style="'+STYLE+'" xmlns:number="'+NUMBER+'" xmlns:fo="'+FO+'" xmlns:x=')+body+SUFFIX).encode()
    styles=('<o:document-styles xmlns:o="'+OFFICE+'" xmlns:style="'+STYLE+'" xmlns:number="'+NUMBER+'" xmlns:fo="'+FO+'" o:version="1.3"><o:styles>'+defs+'</o:styles></o:document-styles>').encode()
    from io import BytesIO
    result=BytesIO()
    with zipfile.ZipFile(BytesIO(package(content))) as base,zipfile.ZipFile(result,'w') as out:
        for info in base.infolist():
            data=base.read(info)
            if info.filename=='META-INF/manifest.xml':
                data=data.replace(b'</manifest:manifest>',b'<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/></manifest:manifest>')
            out.writestr(info,data)
        out.writestr('styles.xml',styles)
    path.write_bytes(result.getvalue())


def effective_cells(path):
    """Inspect effective explicit/default/parent properties using lxml, not MoonODS."""
    with zipfile.ZipFile(path) as z:
        roots=[E.fromstring(z.read(n),E.XMLParser(resolve_entities=False,no_network=True,load_dtd=False)) for n in ['styles.xml','content.xml']]
    defs={};defaults={};numbers={}
    for root in roots:
        for node in root.iter():
            if node.tag=='{'+STYLE+'}style':defs[(node.get('{'+STYLE+'}family'),node.get('{'+STYLE+'}name'))]=node
            elif node.tag=='{'+STYLE+'}default-style':defaults[node.get('{'+STYLE+'}family')]=node
            elif node.tag.startswith('{'+NUMBER+'}') and node.get('{'+STYLE+'}name'):numbers[node.get('{'+STYLE+'}name')]=node
    def canonical(node,root=True):
        return [node.tag,sorted((k,v) for k,v in node.attrib.items() if not (root and k=='{'+STYLE+'}name')),
                node.text if node.tag=='{'+NUMBER+'}text' else (node.text or '').strip(),[canonical(c,False) for c in node]]
    def props(node,seen=()):
        if node is None:return {}
        parent=node.get('{'+STYLE+'}parent-style-name');result={}
        if parent:
            if parent in seen or len(seen)>=16:raise ValueError('style cycle/depth')
            if ('table-cell',parent) not in defs:raise ValueError('missing style parent')
            result.update(props(defs[('table-cell',parent)],seen+(parent,)))
        for child in node:
            if not child.tag.endswith('-properties'):raise ValueError('unsupported style child')
            for key,value in child.attrib.items():result[child.tag+'@'+key]=value
        if node.get('{'+STYLE+'}data-style-name') is not None:result['#number']=canonical(numbers[node.get('{'+STYLE+'}data-style-name')])
        return result
    table=roots[1].find('.//t:table',NS);result={};col_defaults={};col=0
    for node in ordered_columns(table):
        repeat=int(node.get('{'+TABLE+'}number-columns-repeated','1'))
        require(1<=repeat<=128 and col+repeat<=128,'format oracle column budget')
        for _ in range(repeat):
            col_defaults[col]=node.get('{'+TABLE+'}default-cell-style-name');col+=1
    rowno=0
    for row in ordered_rows(table):
        repeat=int(row.get('{'+TABLE+'}number-rows-repeated','1'));require(1<=repeat<=1024 and rowno+repeat<=1024,'format oracle row budget')
        for r in range(rowno,rowno+repeat):
            col=0
            for cell in row:
                count=int(cell.get('{'+TABLE+'}number-columns-repeated','1'));require(1<=count<=128 and col+count<=128,'format oracle column budget')
                for c in range(col,col+count):
                    name=cell.get('{'+TABLE+'}style-name') or row.get('{'+TABLE+'}default-cell-style-name') or col_defaults.get(c)
                    effective=props(defaults.get('table-cell'))
                    if name:
                        require(('table-cell',name) in defs,'missing style definition')
                        effective.update(props(defs[('table-cell',name)]))
                    result[f'{r},{c}']=effective
                col+=count
        rowno+=repeat
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--moon',default='moon');p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);report={'status':'RUNNING','steps':[],'scope':__doc__}
    def run(name,cmd,env=None,expected=0):
        step={'name':name,'command':[str(c) for c in cmd],'exit_code':None,'expected_exit':expected,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()};report['steps'].append(step)
        if env is not None:step['environment_overrides']={k:v for k,v in env.items() if k.startswith('ODS_')}
        r=subprocess.run(step['command'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=120);step['exit_code']=r.returncode
        (out/(name+'.log')).write_text(r.stdout+r.stderr);require(r.returncode==expected,name+' exit mismatch');return r.stdout
    def cli(name,source):
        dest=out/(name+'.ods');before=sha(source);env={k:v for k,v in os.environ.items() if not k.startswith('ODS_')};env.update(ODS_INPUT=str(source),ODS_OUTPUT=str(dest),ODS_ACCEPT_LOSS='1',ODS_PRESERVE_BASIC='1')
        log=run(name,['node',js],env);require(sha(source)==before,'input changed');return dest,log
    try:
        run('build',[a.moon,'build','--target','js','--deny-warn','-j','1','examples/ods_tool'])
        js=next(x for x in [ROOT/'_build/js/debug/build/examples/ods_tool/ods_tool.js',ROOT/'_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js'] if x.exists())
        source=out/'synthetic-style-input.ods'
        body='<t:table-row t:default-cell-style-name="ActualHeader"><t:table-cell t:style-name="Header" o:value-type="string"><x:p>misleading name</x:p></t:table-cell><t:table-cell o:value-type="string"><x:p>default header</x:p></t:table-cell></t:table-row><t:table-row t:default-cell-style-name="RenamedCell"><t:table-cell o:value-type="float" o:value="1.25"/><t:table-cell t:style-name="Unknown" o:value-type="string"><x:p>unknown format</x:p></t:table-cell></t:table-row>'
        fixture(source,body);output,log=cli('known-and-unknown',source)
        before,after=effective_cells(source),effective_cells(output)
        for pos in ['0,0','0,1','1,0']:require(before[pos]==after[pos],'effective properties/number format mismatch at '+pos)
        require(before['1,1']!=after['1,1'] and 'source=Unknown' in log,'unknown style was guessed or loss not reported')
        require(typed(source)==typed(output),'style workflow changed typed data')
        with zipfile.ZipFile(output) as z:require(b'#FF0000' not in z.read('styles.xml'),'unsupported source formatting copied')
        # Mutation proves comparison sees property changes, not just typed values.
        mutant=out/'mutated-style-output.ods'
        with zipfile.ZipFile(output) as z,zipfile.ZipFile(mutant,'w') as changed:
            for info in z.infolist():changed.writestr(info,z.read(info).replace(b'#FFF2CC',b'#00FF00') if info.filename=='styles.xml' else z.read(info))
        require(typed(mutant)==typed(output),'style-only mutation unexpectedly changed values')
        require(effective_cells(mutant)['0,0']!=after['0,0'],'style oracle ignored corrupted color')
        default_changed=out/'unsupported-effective-default-input.ods'
        changed_defs=DEFS.replace('<style:default-style style:family="table-cell"/>','<style:default-style style:family="table-cell"><style:table-cell-properties fo:wrap-option="wrap"/></style:default-style>')
        fixture(default_changed,'<t:table-row><t:table-cell t:style-name="RenamedCell" o:value-type="float" o:value="1.25"/></t:table-row>',changed_defs)
        dropped,default_log=cli('unsupported-effective-default',default_changed)
        require(typed(dropped)==typed(default_changed),'unsupported default changed numeric data')
        require(effective_cells(dropped)['0,0']!=effective_cells(default_changed)['0,0'] and 'source=RenamedCell' in default_log,'unrepresentable effective default was falsely claimed preserved')
        summary=out/'summary-input.ods'
        header='<t:table-header-rows><t:table-row><t:table-cell t:style-name="Header" o:value-type="string"><x:p>real header</x:p></t:table-cell></t:table-row></t:table-header-rows>'
        fixture(summary,header+'<t:table-rows><t:table-row t:number-rows-repeated="40"><t:table-cell t:style-name="Unknown" o:value-type="float" o:value="7"/></t:table-row></t:table-rows>')
        saved,notices=cli('summary',summary)
        require('FORMATTING_DROPPED_SUMMARY' in notices and '8 additional occurrences' in notices,'new formatting loss path not counted beyond32')
        require(typed(saved)==typed(summary) and typed(saved)['Input']['0,0']['text']=='real header','header/body oracle did not preserve document order')
        report.update(status='PASS',checks=['three effective preset/default/inherited/number-style property comparisons','unknown same-name style loss','same-values corrupted-color negative control','new loss path32 details+8 counted summary','header/body content included in typed equality'],inputs={source.name:sha(source),summary.name:sha(summary)})
    except Exception as exc:
        report.update(status='FAIL',error=str(exc))
        raise
    finally:
        (out/'receipt.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
