#!/usr/bin/env python3
"""Read task-owned ODS copies with existing Mac Excel; never install or save."""
import argparse, datetime, hashlib, json, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'evidence/office-2026-10-01'

def main():
    global OUT
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,default=OUT)
    OUT=ap.parse_args().output.resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    steps = []
    def command(name, argv, source=None):
        r = subprocess.run(argv, input=source, capture_output=True, text=True, timeout=75)
        (OUT / (name + '.stdout.txt')).write_text(r.stdout)
        (OUT / (name + '.stderr.txt')).write_text(r.stderr)
        if source is not None: (OUT / (name + '.script.txt')).write_text(source)
        steps.append({'name':name,'command':argv,'exit_code':r.returncode})
        if r.returncode: raise RuntimeError(f'{name} failed; retained logs')
        return r.stdout.strip()
    def open_task_file(name, filename, code):
        (OUT / (name+'-open.script.txt')).write_text(code)
        process=subprocess.Popen(['osascript'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        process.stdin.write(code);process.stdin.close();process.stdin=None
        # Office may require a one-file sandbox grant. Never grant a different
        # filename or a directory; user authorized reading these own fixtures.
        grant='tell application "System Events" to tell process "Microsoft Excel"\nif exists window "Open" then\nset prompt to value of static text 1 of splitter group 1 of window "Open"\nif prompt is '+json.dumps('Please select the file "'+filename+'":')+' then\nclick static text '+json.dumps(filename)+' of scroll area 9 of scroll area 1 of browser 1 of splitter group 1 of splitter group 1 of window "Open"\nif enabled of button "Grant Access" of splitter group 1 of window "Open" then click button "Grant Access" of splitter group 1 of window "Open"\nreturn "Granted only expected task file"\nend if\nend if\nreturn "No expected grant dialog"\nend tell\n'
        (OUT / (name+'-grant.script.txt')).write_text(grant)
        for attempt in range(8):
            if process.poll() is not None: break
            command(name+'-grant-'+str(attempt),['osascript'],grant)
            time.sleep(1)
        stdout,stderr=process.communicate(timeout=60)
        (OUT / (name+'-open.stdout.txt')).write_text(stdout)
        (OUT / (name+'-open.stderr.txt')).write_text(stderr)
        steps.append({'name':name+'-open','command':['osascript'],'exit_code':process.returncode})
        if process.returncode: raise RuntimeError(name+' open failed')
    report={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'application':'Microsoft Excel',
            'scope':'existing Mac application, read operations on task-owned ODS copies, no workbook save; application may report readOnly=false', 'steps':steps,
            'libreoffice':'NOT TESTED; no installation approved','other_applications':'NOT TESTED'}
    try:
        hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (OUT/'inputs').glob('moonods-*.ods')}
        values={}
        for name in ['sales','experiment','formulas','edge']:
            filename='moonods-'+name+'.ods'
            p=OUT/'inputs'/filename
            code='tell application "Microsoft Excel"\nif exists workbook '+json.dumps(filename)+' then return name of workbook '+json.dumps(filename)+'\nset f to (POSIX file '+json.dumps(str(p))+') as text\nopen workbook workbook file name f read only true add to mru false\nreturn name of workbook '+json.dumps(filename)+'\nend tell\n'
            open_task_file(name,filename,code)
            js="var e=Application('Microsoft Excel'); var w=e.workbooks.byName("+json.dumps(filename)+"); var s=w.worksheets[0];\n"
            js+="var result={version:e.version(),name:w.name(),sheets:w.worksheets.name(),readOnly:w.readOnly(),date1904:w.date1904()};\n"
            if name=='sales':
                js+="result.values=s.ranges.byName('A1:D5').value2(); result.date=s.ranges.byName('A3').stringValue(); result.merged=s.ranges.byName('A1').mergeCells(); result.mergeWidth=s.ranges.byName('A1').mergeArea.width(); result.headerRgb=s.ranges.byName('A1').interiorObject.color(); result.headerBold=s.ranges.byName('A1').fontObject.bold(); result.decimalFormat=s.ranges.byName('D3').numberFormat(); result.dateFormat=s.ranges.byName('A3').numberFormat(); result.columnWidthsReported=['A1','B1','C1','D1'].map(c=>s.ranges.byName(c).width());\n"
            elif name=='experiment':
                js+="result.values=s.ranges.byName('A1:D3').value2(); result.date=s.ranges.byName('A2').stringValue(); result.metadata=w.worksheets[1].ranges.byName('B1').value2(); result.longText=w.worksheets[1].ranges.byName('B2').value2();\n"
            elif name=='formulas':
                js+="result.values=s.ranges.byName('A1:B4').value2(); result.formulas=s.ranges.byName('A1:B4').formula(); result.date=s.ranges.byName('B3').stringValue();\n"
            else:
                js+="result.cells=['A1','A2','A3','A4','A5','A6','A7','A8'].map(c=>({address:c,value:s.ranges.byName(c).value2(),type:typeof s.ranges.byName(c).value2()})); result.text=s.ranges.byName('A1').value2(); result.longText=s.ranges.byName('A9').value2(); result.dateDisplays=['A7','A8'].map(c=>s.ranges.byName(c).stringValue());\n"
            js+='JSON.stringify(result);\n'
            values[name]=json.loads(command(name+'-read',['osascript','-l','JavaScript'],js))
        report['version']=values['sales']['version']
        report['readback']=values
        count=0
        def expect(actual, expected):
            nonlocal count
            assert actual==expected,(actual,expected)
            count+=1
        s=values['sales']; expect(s['sheets'],['销售报表']); expect(s['date'],'2026-10-01')
        expect(s['values'][2][1:],[ '月光笔 <限定>&"版"',12,359.88]); expect(s['values'][4][2:],[20,399.88])
        expect(s['merged'],True); expect(s['headerRgb'],[23,50,77]); expect(s['headerBold'],True); expect(s['decimalFormat'],'0.00')
        widths=s['columnWidthsReported']; expected_mm=[32,64,24,34]
        mm_check=all(abs(p-mm*72/25.4)<2 for p,mm in zip(widths,expected_mm))
        report['column_widths']={'reported':widths,'declared_mm':expected_mm,
                                'assuming_points_mm_check':'PASS' if mm_check else 'FAIL',
                                'absolute_physical_mm':'UNRESOLVED; reported units/calibration need separate validation',
                                'relative_proportions':'PASS' if all(abs(p/widths[0]-mm/32)<0.02 for p,mm in zip(widths,expected_mm)) else 'FAIL'}
        assert abs(s['mergeWidth']-sum(widths))<2
        x=values['experiment']; expect(x['sheets'],['样本','元数据']); expect(x['date'],'2024-02-29')
        expect(x['values'][1][1:],[ -0.125,True,' 中文  双空格\t制表\n下一行 😀 ']); expect(x['values'][2][1:],[0,False,''])
        expect(x['metadata'],'合成测试数据，无个人信息'); expect(x['longText'],'长文与XML<&>转义。'*1000)
        f=values['formulas']; expect(f['values'][2][0],30); expect(f['values'][0][1],True)
        expect(f['values'][1][1],'中文 & 结果'); expect(f['date'],'2026-10-01')
        expect(f['formulas'][2][0],'=SUM(A1:A2)'); expect(f['formulas'][0][1],'=A1<A2')
        report['normal_cases']={'status':'PASS','assertion_groups':count,
                                'empty_value_note':'Excel value2 presents both explicit Empty and Text("") as empty string; independent ODS check distinguishes them'}
        # Boundary differences are observations, not suppressed or called PASS.
        edge=values['edge']; issues=[]
        if not mm_check: issues.append('Absolute column-width check assuming points failed; physical-mm calibration unresolved')
        original=' <&>"\'\t\n\r 😀 中文 '
        if edge['text']!=original: issues.append('XML-special/whitespace text differs in Excel')
        if edge['longText']!='x'*32767: issues.append('32767-character text differs in Excel')
        if edge['cells'][3].get('value')!=1e300 or edge['cells'][4].get('value')!=1e-300: issues.append('Extreme finite numbers differ in Excel')
        if edge['cells'][6].get('value') is None: issues.append('Year 0001 date has no value through Excel value2 API')
        if edge['cells'][7].get('value')!=2958465: issues.append('Year 9999 date has unexpected Excel serial')
        report['boundaries']={'status':'PASS' if not issues else 'PARTIAL','issues':issues,
                              'long_text_length_read':len(edge['longText']),'date_displays':edge['dateDisplays']}
        assert hashes=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (OUT/'inputs').glob('moonods-*.ods')},'Input changed by application'
        report['inputs_unchanged_sha256']=hashes
        report['status']='PASS' if not issues else 'PARTIAL'
    except Exception as error:
        report['status']='FAIL';report['error']=str(error)
    report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    (OUT/'excel.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ['readback','steps']},ensure_ascii=False,indent=2))
    return 1 if report['status']=='FAIL' else 0

if __name__=='__main__': raise SystemExit(main())
