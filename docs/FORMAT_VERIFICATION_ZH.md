# 2026-10-03：跨文字字重与实际格式回存

以下是10/3同步前试验记录。当前GitHub源码同步见[同步记录](GITHUB_SYNC_ZH.md)；0.2.0仍未发布到Mooncakes。

本地0.2.0候选，未push、发布或报名。本记录是AI辅助工程事实，不是人工最终申报书，也不是官方验收结论。

## 缺口与修复

Header原来只有`fo:font-weight="bold"`。实际续读官方ODF1.3 XML规范§20.193、§20.294、§20.295及SHA锁定的document RNG发现：拉丁、亚洲、复杂文字各有字重属性。原声明不能充分表达中文表头粗体意图。现为Header补充`style:font-weight-asian="bold"`及`style:font-weight-complex="bold"`，保留五种样式和原API。

用新检验器重新检查10/2真实Calc原生回存文件，6项亚洲/复杂字重断言FAIL、其余44项PASS；旧文件未重新调用应用。原CLI退出1、检查器摘要、原应用报告摘要与旧style.mbt摘要保留在`evidence/overnight-2026-10-03/baseline-formatting*`。这是存储样式声明缺口的规范与属性证据，不冒称修复前中文屏幕截图或字体渲染实测。

## 实际复核

完整验收仍为31核心/API与5独立消费PASS；未通过新增机械单元断言凑测试数。独立源包校验同时核Header的三种字重，官方RNG继续通过。四主例、日期单位例、三消费例均由两个生成进程分别输出同样字节。

复用已装`LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`，一次性profile实际导入8个新生成的无宏ODS并原生回存；未安装或改变全局字体、未开放服务监听。33类型值及2合并PASS，源输入SHA未改变。

应用回存由odfpy读取，新增50个属性断言全部PASS：18项Header颜色/环绕/三文字字重，3项Highlight/Plain属性，6项Decimal2小数位/对齐，4项ISO日期模式，1项Calc显示文本，18项列宽。实验-0.125仍是底层数值，Calc回存显示-0.13，显示精度没有截断数据。日期检查解析实际单元格→行默认→列默认→样式父链，而非只寻找一个未被引用的DateISO定义；Calc可能把日期样式提升为列默认，并改写样式名字。

列宽比较实际回存的`in`长度和原1/32/500mm等请求值，预先声明0.02mm容差覆盖应用量化/小数序列化；18项在此容差内通过。**这证明此应用路径保存了近似等长的ODF属性，不证明屏幕像素、纸面实物毫米或Excel的JXA单位。** 不向writer增加猜测的像素补偿。

另有7个检验器负控制：亚洲字重改normal、宽度偏1mm、改三位小数、改短年份、列日期默认替换Plain、循环父样式及缺失父样式，全部按预期拒绝。它们只修改真实应用输出的odfpy内存对象，不调用Office，不称LibreOffice拒绝7坏文件。完整固定断言保持同一预期，没有修改失败标准。

实际命令、退出码、原生回存文件和详细属性/控制在`evidence/overnight-2026-10-03/libreoffice-formatting/libreoffice.json`。可复现命令见README；单独重新检查已有回存文件可运行：

```sh
python scripts/verify_formatting.py \
  --input evidence/overnight-2026-10-03/libreoffice-formatting \
  --report /tmp/moonods-saved-formatting.json
```

这个命令不启动应用；新应用验证必须用`verify_libreoffice.py`及明确指定的现有工具路径。检验器仅面向固定有界测试样本，没有为库新增读取/转换能力。

## 证据边界

所有ODS样式字节均已改变。10/1 Excel常规20组与10/2 LibreOffice原记录保留为历史实测，不能以其旧哈希证明本候选已经在Excel打开；当前acceptance会将旧Excel关联标为STALE INPUTS。当前新文件的实际应用验证是本轮LibreOfficeDev。稳定版、GUI字形/打印、绝对物理毫米、Numbers/WPS、其他后端、峰值RSS与性能仍未测，整体Office兼容状态PARTIAL。当前候选远端CI未运行、0.2.0未发布。

规范来源：[OASIS ODF1.3 XML](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)、[官方document RNG](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema.rng)。网页工具因正文大小无法提取，本轮确实读取任务已有官方原文快照的相关正文，并实际读取当前SHA锁定RNG定义；没有把搜索摘要当正文。只记录事实摘要，不分发整篇官方规范。
