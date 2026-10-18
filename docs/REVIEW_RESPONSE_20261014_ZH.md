# 初审整改范围核对与阻塞（AI辅助技术底稿）

接续原 main `3772f50e5e752fef5c8a6231c81c01ff95b4e93c`，正式版本仍为 0.2.0；分支 `review/typed-roundtrip-20261014`。本次未 push、dispatch、发布、重申或改生产。规则仍保留已有完整阅读快照；本轮飞书章程/表单访问失败，不宣称再次完整核读。

| 官方问题 | 当前事实 | 必要增量 | 本轮状态 |
|---|---|---|---|
| writer范围窄 | 已有 Empty/Text/finite Number/Boolean/Gregorian Date、formula+typed cache、合并、编辑、确定性输出 | 外部ODS→有界类型化读取→受支持格编辑→写回 | reader尚未实现；不是“已支持读改写” |
| 已有读取库 | markitdown 已有 ODS internal text/formula/merge/repeat 与有界读取 | 对外稳定的类型值/独立缓存/编辑/逐格诊断 | 差异可提出，但价值未经外部闭环证明 |
| 增量价值不足 | 现有单独writer与自身fixture不足 | 与mbtexcel公共接口互补的实际消费者 | 尚未实现/运行，评审价值问题仍未解决 |
| 申报已实现/计划区分 | 正式0.2.0已有历史发布与应用证据 | 修正旧状态句，历史证据只对应旧源码 | 文档修正完成，不计作核心增量 |

## 生态来源与复用判断

[markitdown](https://github.com/ZSeanYves/markitdown) 当前读取源码的 OdsCell 含 text/formula/column_span/row_span/covered/repeat_count；公开产品用于 Markdown/Debug/RAG 输出。README 明确内部 readers、parser records、IR 不是 consumer API。不能声称它没有读取，也不依赖 internal 包做本库公共契约。当前模型提取文本、公式和结构，不等于本项目已有 Value+独立cache 的编辑模型；这只是可验证差异，不保证官方认可新增价值。

[mbtexcel](https://github.com/moonbitlang/office.mbt/tree/main/mbtexcel) 已有 XLSX 公共 read/write、get/set typed values、merge_cells、日期和公式接口。首轮跨格式消费者应单独依赖其公共模块；不自建 XLSX 引擎、不复制其内部实现。其公开 CellValue 没有 Date/Empty直接分支，需制定空格/空字符串、日期系统及支持范围映射。

参考提交及文件 SHA256 见 `evidence/review-20261014/environment.json`。外部源码仅在独立 references 目录只读核对，没有复制进本库。

## SDK恢复后可控的首轮范围

复用既有 Cell/Value/Sheet.set/set_row/merge 及 Workbook.to_ods。新入口接完整外部ODS bytes，成功返回 workbook 和结构化诊断；错误不返回貌似可写回的部分成功。诊断含 code、sheet、零起点row/col、operation、是否拒绝或损失，以及原类型/feature，不以一个笼统warning吞掉每个受影响格。

| 输入 | 首轮处理 |
|---|---|
| Empty与空字符串 | 保留区别；covered格单独处理；不能把空字符串当缺格 |
| float/boolean/date | 数字必须有限；Gregorian日期仅date-only；date-time/time/currency/percentage等明确拒绝或逐格诊断 |
| 公式 | 保存原OpenFormula文本及独立类型缓存，不求值；无缓存当前Cell.formula不接受，首轮显式拒绝，不假造缓存 |
| 简单文本 | 保留空白、text:s、tab、line-break与段落；不trim；丰富文本样式丢弃需显式诊断 |
| 简单合并 | 保留anchor/covered网格；拒绝重叠、越界或covered中非空数据 |
| 超出writer表示范围的样式、列行属性、图表/图像/宏/外部链接 | 明确拒绝或损失诊断；不默默写回成“无损” |

读取前限制ZIP总输入32MiB、entry数、单entry/累计解压字节、压缩比；检查重复名称、加密/不支持压缩和异常头；在inflate阶段执行实际输出字节预算，不能只相信central directory。XML UTF-8输入、字节/节点/深度/属性/文本额度；禁止DTD、ENTITY及任何外部解析。namespace按URI，不仅按固定prefix。重复行列先验证乘积/总grid预算后展开，首轮沿用writer 32 sheets、1024 rows/128 cols、65536 sheet grid、262144 workbook grid、text预算；不能把超预算外部尾部静默裁剪为可无损写回。

这些是待实现的合同，不是已验证的安全能力；不能因校验器能读取而宣称库能读取。

## 跨格式首轮选择

优先选择显式**拒绝公式转换**，保留ODS编辑写回中的原公式；若应用明确选择cache-only export，逐公式格报 `FORMULA_DROPPED`，缓存无类型/缺失则拒绝。日期用mbtexcel公共日期接口，明确1900系统且限制>=1900-01-01，拒绝虚构1900-02-29；ODS更早日期不隐式转文本或浮点。读取XLSX输出应分别核类型、空字符串、数字、boolean、日期语义和合并，不能只核显示字符串。常规数值/文本/boolean先形成独立消费者闭环再扩日期。

## 必须补的证据（本轮未产生）

1. 至少两个真正外部ODS来源，LibreOffice官方 `sc/qa/unit/data/ods` 中挑选前核相应版本的许可、内容、宏/链接、尺寸与profile；记录commit、原URL、hash与选择理由。GitHub API目录请求本轮被403拒绝，未下载、纳入或声称已检查fixtures。
2. 外部bytes实际走MoonBit reader，核类型/cache/merge，受支持格编辑并写回；Python独立语义核读前后值与逐格损失，不用reader自证自身输出。
3. 重复展开/ZIP膨胀/错误长度/DTD实体/错误namespace等负控制；失败先于大分配/外部访问。
4. 稳定LibreOffice隔离profile开存再核语义。当前环境只有LibreOfficeDev 26.8 alpha，历史已有Dev证据继续保留，不能改称稳定版或GUI验收。
5. 单独MoonBit消费者通过mbtexcel公共API导出XLSX并由其读取，以及独立工具语义检查。不能用Python替代MoonBit跨格式消费者。

## 未完成原因与取舍

本环境无moon/moonc，官方安装脚本HTTP403，未执行安装或绕过；既有工具链Node/Python锁与当前环境也不一致。没有可编译测试的条件，故未增添不能验证的ZIP/XML reader及mbtexcel耦合实现。原writer源码及版本不变，仅修正文档事实并留下有界方案。**外部读改写与真正跨格式消费闭环未交付，核心整改目标及ODS增量价值仍未解决。**恢复已有授权可用SDK后再实施上述最小范围；不以扩大无损承诺替代证据。
