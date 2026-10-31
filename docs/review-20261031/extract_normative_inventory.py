from lxml import html
from pathlib import Path
import re,json,csv,collections
base=Path(__file__).resolve().parent;out=[]; seen=set()
for n in [1,2,3,4]:
 p=base/'standards'/f'part{n}.html'; root=html.fromstring(p.read_bytes());section=''
 for e in root.iter():
  if e.tag not in ['h1','h2','h3','h4','h5','p','li']:continue
  t=' '.join(e.text_content().split())
  if e.tag.startswith('h'):section=t
  if re.search(r'implementation[- ]defined',t,re.I):
   key=(n,section,t)
   if key not in seen:out.append({'part':n,'section':section,'text':t});seen.add(key)
(base/'standards/implementation-defined-by-clause.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
with (base/'implementation-defined_条款分类.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['part','section','classification','scope'])
 for r in out:
  n=r['part'];s=r['section'];code=s.split(' ')[0]
  if code.startswith(('1.2','1.3','2.3','2.4')) or not s:c='定义/义务/目录';note='不是独立输出功能'
  elif n==4:c='公式求值器范围';note='本库不托管通用求值器；不据此宣称函数行为通过'
  elif n==2 and code=='4.16.11':c='需说明';note='无GUI；不选择/保留默认视图；消费应用决定'
  elif n==3 and code=='19.646':c='需说明';note='输出公式文本和外部缓存；无求值HOST-LOCALE'
  elif n==3 and code=='20.230':c='需说明';note='部分样式显式wrap；其他未指定；不渲染溢出'
  else:c='当前writer未使用相关机制';note='固定词汇/四部件核查；并不承诺所有输入均可读取'
  w.writerow([n,s,c,note])
print('counts',dict(collections.Counter(r['part'] for r in out)),'total',len(out))
