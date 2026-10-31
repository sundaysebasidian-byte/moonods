#!/usr/bin/env python3
"""Prepare independent-producer and hostile reader fixtures. Does NOT execute MoonODS."""
import argparse, hashlib, json, struct, subprocess, tempfile, warnings, zipfile
from io import BytesIO
from pathlib import Path
from lxml import etree

ROOT=Path(__file__).resolve().parents[1]
MIME=b'application/vnd.oasis.opendocument.spreadsheet'
OFFICE='urn:oasis:names:tc:opendocument:xmlns:office:1.0'
TABLE='urn:oasis:names:tc:opendocument:xmlns:table:1.0'
TEXT='urn:oasis:names:tc:opendocument:xmlns:text:1.0'
NS={'o':OFFICE,'t':TABLE,'x':TEXT}
PREFIX='<o:document-content xmlns:o="'+OFFICE+'" xmlns:t="'+TABLE+'" xmlns:x="'+TEXT+'" o:version="1.3"><o:body><o:spreadsheet><t:table t:name="Input">'
SUFFIX='</t:table></o:spreadsheet></o:body></o:document-content>'

def package(content,compression=zipfile.ZIP_STORED,duplicate=False):
    out=BytesIO()
    manifest=b'<?xml version="1.0"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/><manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>'
    files=[('mimetype',MIME),('content.xml',content),('META-INF/manifest.xml',manifest)]
    if duplicate:files.append(('content.xml',content))
    with zipfile.ZipFile(out,'w') as z:
        for name,data in files:
            info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_STORED if name=='mimetype' else compression
            info.external_attr=0o100644<<16
            with warnings.catch_warnings():
                warnings.simplefilter('ignore',UserWarning);z.writestr(info,data)
    return out.getvalue()

def controls():
    def xml(s):return (PREFIX+s+SUFFIX).encode()
    typed='<t:table-row><t:table-cell o:value-type="string"><x:p/></t:table-cell><t:table-cell/><t:table-cell o:value-type="float" o:value="1.25"/><t:table-cell o:value-type="boolean" o:boolean-value="false"/><t:table-cell o:value-type="date" o:date-value="2024-02-29"/></t:table-row>'
    cases={
      'typed-prefix-alias.ods':(package(xml(typed)),'ACCEPT_TYPED_EMPTY_VS_STRING'),
      'repeat-overflow.ods':(package(xml('<t:table-row t:number-rows-repeated="2147483647"><t:table-cell t:number-columns-repeated="2147483647"/></t:table-row>')),'REJECT_REPEAT_BUDGET'),
      'nonfinite-number.ods':(package(xml('<t:table-row><t:table-cell o:value-type="float" o:value="INF"/></t:table-row>')),'REJECT_NONFINITE'),
      'invalid-date.ods':(package(xml('<t:table-row><t:table-cell o:value-type="date" o:date-value="1900-02-29"/></t:table-row>')),'REJECT_INVALID_DATE'),
      'formula-without-cache.ods':(package(xml('<t:table-row><t:table-cell xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2" t:formula="of:=1+2"/></t:table-row>')),'REJECT_OR_EXPLICIT_MISSING_CACHE_DIAGNOSTIC'),
      'unknown-currency.ods':(package(xml('<t:table-row><t:table-cell o:value-type="currency" o:currency="USD" o:value="5"/></t:table-row>')),'EXPLICIT_UNSUPPORTED_CELL_DIAGNOSTIC'),
      'duplicate-content.ods':(package(xml(typed),duplicate=True),'REJECT_DUPLICATE_ENTRY'),
      'wrong-table-namespace.ods':(package(xml(typed).replace(TABLE.encode(),b'urn:wrong-table')),'REJECT_WRONG_NAMESPACE'),
      'deep-xml.ods':(package(xml('<t:table-row><t:table-cell>'+'<x:span>'*256+'x'+'</x:span>'*256+'</t:table-cell></t:table-row>')),'REJECT_XML_DEPTH'),
      'dtd-entity.ods':(package(b'<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "http://127.0.0.1:9/moonods-never-fetch">]>'+xml('<t:table-row><t:table-cell o:value-type="string"><x:p>&e;</x:p></t:table-cell></t:table-row>')),'REJECT_EXTERNAL_DEPENDENCY_WITHOUT_NETWORK'),
      'inflate-ratio.ods':(package(xml('<t:table-row><t:table-cell o:value-type="string"><x:p>'+'A'*262144+'</x:p></t:table-cell></t:table-row>'),zipfile.ZIP_DEFLATED),'REJECT_OR_BOUND_ACTUAL_INFLATE_OUTPUT'),
    }
    forged=bytearray(cases['inflate-ratio.ods'][0])
    # Lie about both local and central uncompressed sizes, while preserving a
    # real larger DEFLATE stream. Readers must enforce actual output budgets.
    for magic,offset,nameoffset in [(b'PK\x03\x04',22,30),(b'PK\x01\x02',24,46)]:
        at=0
        while True:
            at=forged.find(magic,at)
            if at<0:break
            n=struct.unpack_from('<H',forged,at+(26 if nameoffset==30 else 28))[0]
            if bytes(forged[at+nameoffset:at+nameoffset+n])==b'content.xml':struct.pack_into('<I',forged,at+offset,1)
            at+=4
    cases['forged-inflate-size.ods']=(bytes(forged),'REJECT_OR_BOUND_ACTUAL_INFLATE_OUTPUT_NOT_DECLARED_SIZE')
    return cases

def fixed_producer_xml(path):
    # Independent fixed-fixture oracle, not the MoonBit reader under test.
    with zipfile.ZipFile(path) as z:
        if len(z.infolist())>128:raise ValueError('oracle entry budget')
        info=z.getinfo('content.xml')
        if info.file_size>4*1024*1024:raise ValueError('oracle XML budget')
        with z.open(info) as stream:data=stream.read(4*1024*1024+1)
        if len(data)>4*1024*1024:raise ValueError("oracle actual XML budget")
    if b'<!DOCTYPE' in data or b'<!ENTITY' in data:raise ValueError('DTD forbidden')
    return etree.fromstring(data,etree.XMLParser(resolve_entities=False,no_network=True,load_dtd=False,huge_tree=False))

def text_space_count(raw):
    """ODF text:c is XSD nonNegativeInteger; bound before large-int parsing."""
    import re
    token = raw.strip(' \t\r\n')
    if not re.fullmatch(r'[+-]?[0-9]+', token):
        raise ValueError('fixed-fixture text repeat lexical form')
    negative = token.startswith('-')
    digits = token[1:] if token[:1] in ('+', '-') else token
    significant = digits.lstrip('0') or '0'
    if (negative and significant != '0') or len(significant) > 5:
        raise ValueError('fixed-fixture text repeat budget')
    count = int(significant)
    if count > 32767:
        raise ValueError('fixed-fixture text repeat budget')
    return count

def text_of(node):
    # Independent ODF 1.3 section 6.1.2 oracle: flatten span text, normalize
    # raw XML whitespace, then expand explicit controls. NUL is forbidden
    # in XML, so it is a collision-free internal placeholder, never output.
    import re
    pieces, controls = [], []
    def raw(text):
        if '\0' in text: raise ValueError('illegal XML NUL in oracle')
        pieces.append(text)
    def visit(element):
        raw(element.text or '')
        for child in element:
            if child.tag == '{'+TEXT+'}s':
                count = text_space_count(child.get('{'+TEXT+'}c', '1'))
                controls.append(' ' * count); pieces.append('\0')
            elif child.tag == '{'+TEXT+'}tab':
                controls.append('\t'); pieces.append('\0')
            elif child.tag == '{'+TEXT+'}line-break':
                controls.append('\n'); pieces.append('\0')
            else:
                visit(child)
            raw(child.tail or '')
    visit(node)
    normalized = re.sub(r'[ \t\r\n]+', ' ', ''.join(pieces)).strip(' ')
    chunks = normalized.split('\0')
    out = chunks[0] + ''.join(control + tail for control, tail in zip(controls, chunks[1:]))
    if len(out) > 32767: raise ValueError('fixed-fixture text length budget')
    return out

def ordered_rows(sheet):
    """Bounded direct-child expansion in document order, not descendant search."""
    row = '{'+TABLE+'}table-row'
    column = '{'+TABLE+'}table-column'
    row_containers = {'{'+TABLE+'}table-header-rows', '{'+TABLE+'}table-rows'}
    col_containers = {'{'+TABLE+'}table-header-columns', '{'+TABLE+'}table-columns'}
    physical = 0
    for child in sheet:
        if child.tag == column:
            continue
        if child.tag == row:
            physical += 1
            if physical > 65536:
                raise ValueError('oracle physical row budget')
            yield child
        elif child.tag in row_containers | col_containers:
            if child.attrib:
                raise ValueError('oracle unsupported row/column container attributes')
            expected = row if child.tag in row_containers else column
            if not len(child):
                raise ValueError('oracle empty row/column container')
            for nested in child:
                if nested.tag != expected:
                    raise ValueError('oracle unsupported nested row/column container')
                if expected == row:
                    physical += 1
                    if physical > 65536:
                        raise ValueError('oracle physical row budget')
                    yield nested
        else:
            raise ValueError('oracle unsupported table child: '+str(child.tag))


def ordered_columns(sheet):
    """Expand the supported column containers without losing document order."""
    column = '{'+TABLE+'}table-column'
    row = '{'+TABLE+'}table-row'
    col_containers = {'{'+TABLE+'}table-header-columns', '{'+TABLE+'}table-columns'}
    row_containers = {'{'+TABLE+'}table-header-rows', '{'+TABLE+'}table-rows'}
    physical = 0
    for child in sheet:
        if child.tag == row:
            continue
        if child.tag == column:
            physical += 1
            if physical > 128:
                raise ValueError('oracle physical column budget')
            yield child
        elif child.tag in col_containers | row_containers:
            if child.attrib or not len(child):
                raise ValueError('oracle unsupported/empty row/column container')
            expected = column if child.tag in col_containers else row
            for nested in child:
                if nested.tag != expected:
                    raise ValueError('oracle unsupported nested row/column container')
                if expected == column:
                    physical += 1
                    if physical > 128:
                        raise ValueError('oracle physical column budget')
                    yield nested
        else:
            raise ValueError('oracle unsupported table child: '+str(child.tag))


def semantics(path):
    root=fixed_producer_xml(path);result={};tails=[]
    for sheet in root.findall('.//t:table',NS):
        name=sheet.get('{'+TABLE+'}name');cells={};rowno=0
        if name in result or len(result)>=32:raise ValueError('oracle duplicate sheet or sheet budget')
        for row in ordered_rows(sheet):
            repeat_rows=int(row.get('{'+TABLE+'}number-rows-repeated','1'));col=0
            if not 1<=repeat_rows<=1048576:raise ValueError('oracle row repeat budget')
            for cell in row:
                if cell.tag not in ['{'+TABLE+'}table-cell','{'+TABLE+'}covered-table-cell']:raise ValueError('oracle unsupported row child')
                repeat_cols=int(cell.get('{'+TABLE+'}number-columns-repeated','1'));kind=cell.get('{'+OFFICE+'}value-type')
                if not 1<=repeat_cols<=16384:raise ValueError('oracle column repeat budget')
                meaningful=kind is not None or cell.get('{'+TABLE+'}formula') is not None or cell.tag.endswith('covered-table-cell') or cell.get('{'+TABLE+'}number-columns-spanned') is not None or cell.get('{'+TABLE+'}number-rows-spanned') is not None
                if meaningful:
                    if rowno+repeat_rows>1024 or col+repeat_cols>128:raise ValueError('meaningful cell outside oracle profile')
                    values={k.split('}',1)[-1]:v for k,v in cell.attrib.items() if k.startswith('{'+OFFICE+'}') or k in ['{'+TABLE+'}formula','{'+TABLE+'}number-columns-spanned','{'+TABLE+'}number-rows-spanned']}
                    display='\n'.join(text_of(x) for x in cell.findall('x:p',NS))
                    # office:string-value is authoritative when present, including
                    # an empty value or a legal attribute-only string cell.
                    values['text']=cell.get('{'+OFFICE+'}string-value',display) if kind=='string' else display
                    if cell.tag.endswith('covered-table-cell'):values['covered']=True
                    for r in range(rowno,rowno+repeat_rows):
                        for c in range(col,col+repeat_cols):cells[f'{r},{c}']=values
                col+=repeat_cols
            if rowno+repeat_rows>1024 or col>128:tails.append({'sheet':name,'row':rowno,'repeated_rows':repeat_rows,'logical_columns':col,'note':'Dimensions outside writer profile; not silently accepted by MoonODS'})
            rowno+=repeat_rows
        result[name]=cells
    return {'sheets':result,'outside_writer_grid':tails}

def assert_external_observation(observation):
    cells=observation['sheets']['Types']
    assert cells['0,1']['boolean-value']=='true' and cells['0,2']['date-value']=='2024-02-29'
    assert cells['0,3']['text']==' leading \t中\n文 '
    assert all(cells[f'{r},{c}']['value']=='7.5' for r in [1,2] for c in [0,1])
    assert cells['0,4']['value-type']=='string' and cells['0,4']['text']=='' and '0,5' not in cells
    merged=observation['sheets']['Merge']
    assert merged['0,0']['number-columns-spanned']=='2' and merged['0,0']['number-rows-spanned']=='2'
    assert all(merged[k]['covered'] for k in ['0,1','1,0','1,1']) and merged['1,2']['value']=='42'
    assert cells['0,6']['formula']=='of:=1+2' and cells['0,6']['value-type']=='float' and cells['0,6']['value']=='3'
    return {'cells':cells,'checks':['Boolean','Date','whitespace','repeat2x2','Empty_vs_empty_string','merge2x2_three_covered','formula_text_and_external_cache_3']}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--soffice',type=Path,required=True);a=ap.parse_args()
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    data=controls();again=controls();assert data==again
    controls_dir=out/'controls';controls_dir.mkdir()
    manifest={}
    for name,(payload,expect) in sorted(data.items()):
        (controls_dir/name).write_bytes(payload)
        manifest[name]={'sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload),'expected_moonods_result':expect,'moonods_execution':'NOT_RUN','producer':'independent Python ZIP/XML test data; MIT synthetic, not MoonODS output'}
    (out/'controls-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    report={'scope':'fixture preparation and external-producer semantic observation only; NOT MoonODS reader/edit/write verification','controls_determinism':'PASS_TWO_GENERATIONS','controls_count':len(data),'steps':[],'status':'FAILED'}
    try:
        r=subprocess.run([str(a.soffice.resolve()),'--version'],capture_output=True,text=True,timeout=15);report['application_version']=r.stdout.strip();assert r.returncode==0
        source=ROOT/'tests/reader-fixtures/source/types.fods';report['source_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
        observations=[]
        for i in range(2):
            saved=out/f'external-{i+1}';saved.mkdir()
            with tempfile.TemporaryDirectory(prefix='moonods-fixture-profile-') as td:
                profile=Path(td)/'profile'
                cmd=[str(a.soffice.resolve()),'-env:UserInstallation='+profile.as_uri(),'--headless','--nologo','--nodefault','--norestore','--convert-to','ods:calc8','--outdir',str(saved),str(source)]
                r=subprocess.run(cmd,capture_output=True,text=True,timeout=45)
                (out/f'libreoffice-{i+1}.stdout.txt').write_text(r.stdout);(out/f'libreoffice-{i+1}.stderr.txt').write_text(r.stderr)
                report['steps'].append({'command':cmd,'exit_code':r.returncode});assert r.returncode==0
            book=saved/'types.ods';assert book.is_file()
            observation=semantics(book);observations.append(observation)
            (out/f'semantics-{i+1}.json').write_text(json.dumps(observation,ensure_ascii=False,indent=2)+'\n')
            report[f'external_{i+1}_sha256']=hashlib.sha256(book.read_bytes()).hexdigest()
        assert observations[0]==observations[1]
        validated=assert_external_observation(observations[0]);cells=validated['cells']
        report['semantic_assertions']=validated['checks']
        report['semantic_repeatability']='PASS_TWO_ISOLATED_PROFILES'
        report['external_empty_string_cell']=cells.get('0,4','NO_TYPED_CELL_RETAINED_BY_PRODUCER')
        report['external_formula_cell']=cells['0,6']
        report['outside_writer_grid']=observations[0]['outside_writer_grid']
        report['stable_libreoffice']='NOT_TESTED';report['moonods_reader_edit_write']='NOT_IMPLEMENTED_NOT_RUN';report['mbtexcel_consumer']='NOT_IMPLEMENTED_NOT_RUN'
        report['status']='FIXTURES_PREPARED_CORE_NOT_TESTED'
    except Exception as e:report['error']=str(e)
    (out/'fixture-preparation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2));return 0 if report['status']=='FIXTURES_PREPARED_CORE_NOT_TESTED' else 1
if __name__=='__main__':raise SystemExit(main())
