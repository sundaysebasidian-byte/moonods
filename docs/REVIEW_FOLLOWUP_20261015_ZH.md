# ODS 初审整改续接：外部fixture准备与核心缺口

接续 `80002ab190c9b3adc5de720339d0e028408252d4` 的原审阅分支；正式0.2.0 writer不变，前轮恢复包保留。本轮没有push、Actions、发布或重申。本文为AI辅助工程底稿，不是人工最终申报书。

## 精确评审要求

主线程重读邮件提供的原文：

> ods 本身较为小众，申报项目只做生成功能（writer），那就更小众了，从功能范围来讲非常窄；而且似乎 ods 已经有读取的库了？感觉很难有足够的增量价值。审查驳回。

因此，新增文档或fixture不能当作新增reader；只有外部输入实际通过MoonBit有界类型化读取、受支持格编辑写回、逐格损失诊断及mbtexcel公共API消费闭环，才可能证明所提增量。Markitdown确有ODS内部读取且公开用于Markdown/RAG；不能改称它没有读取。mbtexcel已实现XLSX引擎，不另造替代引擎。

| 事项 | 已有/当前实情 | 本轮可验证进展 | 仍缺 |
|---|---|---|---|
| 原模型 | Empty/Text/finite Number/Boolean/Date、公式与cache、编辑/merge、writer | 保持原库，不重新造工程 | 外部reader入口 |
| 外部ODS | 原历史主要核自家输出在应用中开存 | 独立FODS经LibreOfficeDev保存为真正外部producer ODS；来源/hash/profile记录 | MoonODS读取该输入、编辑并写回 |
| 类型和结构 | 原模型可表示支持子集 | 独立oracle核bool/date、空白、Empty与空字符串、重复格、2×2合并/3covered/42、公式文本与应用cache | MoonBit语义核对及每格诊断 |
| 有界/安全 | writer有界不等于reader有界 | 12个固定ZIP/XML控制数据，两次生成字节相同 | 全部控制交由真实reader执行；实际inflate/展开/实体边界证据 |
| 跨格式价值 | mbtexcel公共API已核 | 未把internal依赖或Python当替代消费者 | 真正MoonBit调用mbtexcel并重读XLSX；公式策略和日期映射 |

## 外部样本与首次失败

`tests/reader-fixtures/source/types.fods` 是本项目MIT合成输入，使用不同namespace前缀，含类型、重复、合并及公式。它没有通过MoonODS writer生成；已有LibreOfficeDev以两次隔离profile实际导入并保存为ODS，原生输出一份冻结在 `tests/reader-fixtures/external/libreoffice-dev-types.ods`，来源、SHA256、应用版本及许可说明见相邻source.json。

这是一个外部producer样本家族的两次运行，不是两个独立外部来源，也不是LibreOffice官方fixtures或稳定版兼容证据。未取得的官方fixtures不宣称已核。

首次输入只有boolean/date值类型、缺少数据样式，Dev导入后将其保存为float 1和45351，oracle按预期类型检查失败；原source、失败报告与观测保留。补齐FODS的Bool/Date数据样式后，两profile输出语义相同，并独立检查：

- true布尔、2024-02-29日期、空字符串独立于空格；空格/Tab/中文/换行保留。
- 两行两列重复7.5；合并anchor 2×2、三个covered格及其旁42。
- 公式文本 `of:=1+2` 仍在；应用将输入cache99重算成3，输出cache独立记录为3。这是外部应用重算，不是MoonODS计算，也不是99缓存无损承诺。

两次ODS **字节不同**，不声称应用输出字节确定；只有观测语义重复一致。12个合成控制ZIP则使用固定条目/时间戳，两次生成逐字节一致。

## 控制样本范围

`controls-manifest.json` 每项标 `moonods_execution: NOT_RUN`，给出未来reader的目标结果。覆盖namespace别名与空值区别、repeat乘积溢出、INF、无效Gregorian日期、无cache公式、currency、重复ZIP entry、错误namespace、深XML、DTD外部实体、压缩高膨胀率、local/central同时谎报解压大小。负样本没有交给LibreOffice或现有odfpy验证器执行。

`prepare_reader_fixtures.py` 的Python解析仅是固定producer样本oracle，已限制XML实际读取及text:s展开；它不是库读取实现，不证明恶意输入经MoonBit有界。现有 `verify_external.py` 只接受自家固定四路径/STORED输出，不能拿它拒绝外部包当成功；现有 `verify_libreoffice.py` 也不是恶意reader gate。

## 当前验收与工具链

外部fixture生成/独立核对的真实结果位于 `evidence/review-20261015/fixtures-first` 与 `fixtures-styled`；首次失败与后续修正均保留。所用应用为LibreOfficeDev 26.8 alpha，lxml6.1.1；odfpy/defusedxml未安装。没有稳定LibreOffice或GUI验证，未替换原锁定版本要求。

MoonBit SDK仍不存在；新授权下正常官方请求仍HTTP403，原因未明确，未执行安装/绕过。原完整acceptance入口实际再试后在缺moon前置检查处退出，未执行核心测试。独立审查仅核fixture/断言/范围及源码，不能算运行reader验收。

**有界外部读取、编辑写回、逐格损失诊断和真实mbtexcel消费尚未实现；初审增量价值问题仍未解决，本项目仍不能称已准备好重申。** 工具链受阻时不继续堆叠未经编译的大型ZIP/XML实现，也不以外部样本准备冒充闭环。
