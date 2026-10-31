from pathlib import Path
from lxml import etree
import hashlib,json,zipfile,collections,argparse
from datetime import datetime, timezone
out=Path(__file__).resolve().parent
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);args=ap.parse_args();src=args.source.resolve();base=out
ident=json.loads((out/'audit_inputs/SOURCE_IDENTITY.json').read_text())
mismatches=[p for p,h in ident['source_files'].items() if not (src/p).exists() or hashlib.sha256((src/p).read_bytes()).hexdigest()!=h]
# These are saved runtime outputs, re-inspected now; not new executions of MoonODS.
cases=json.loads((out/'audit_inputs/positive_cases.json').read_text())
corpus=[out/'audit_inputs/outputs'/name/'output.ods' for name in cases]
results=[]; elements=collections.Counter();attrs=collections.Counter()
for p in corpus:
 with zipfile.ZipFile(p) as z:
  names=z.namelist();assert names==['mimetype','content.xml','styles.xml','META-INF/manifest.xml'],(p,names)
  assert z.testzip() is None
  for n in names[1:]:
   root=etree.fromstring(z.read(n),etree.XMLParser(resolve_entities=False,no_network=True))
   for e in root.iter():
    if isinstance(e.tag,str):elements[e.tag]+=1
    for k in e.attrib:attrs[k]+=1
  results.append({'path':str(p.relative_to(base)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'four_part_profile':True,'crc_ok':True})
report={'audit_time_utc':datetime.now(timezone.utc).isoformat(),'source_binding':ident['commit'],'source_count':len(ident['source_files']),'source_mismatches':mismatches,'scope':'saved final DTD runtime outputs re-inspected, not new CLI execution; no all-producer proof','saved_outputs_checked':len(results),'results':results,'element_names':sorted(elements),'attribute_names':sorted(attrs),'official_source_sha256':json.loads((out/'STANDARD_SOURCES.json').read_text())}
(out/'IMPLEMENTATION_PROFILE_RECEIPT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
assert not mismatches,mismatches
print('source files',len(ident['source_files']),'match; saved outputs',len(results),'pass four-part+CRC; XML vocabulary inventoried')
