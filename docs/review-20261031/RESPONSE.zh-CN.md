# MoonODS：实现范围、损失与验证

本说明介绍实现范围、数据损失与验证方法。AI 协助情况见仓库 AI_USAGE.md。

## 版本与可复现入口

运行代码基线：[897c906607e1ec5072e514599e846bdbe6defe3e](https://github.com/sundaysebasidian-byte/moonods/commit/897c906607e1ec5072e514599e846bdbe6defe3e)，树 `ff36f8b595e36dd45f85bd480fe41c28b63dc441`。本目录只补技术说明、合成样本与审计脚本，不修改库行为。所在分支为 `review/moonbit-20261030`，不是 main 合并或 registry 新发行；0.4.0 注册表包不包含这些复审修复。

2026-10-31 04:50 UTC 留存回执确认上述基线的三项CI成功：[MoonODS checks](https://github.com/sundaysebasidian-byte/moonods/actions/runs/41169963054)、[Fresh clone quick start](https://github.com/sundaysebasidian-byte/moonods/actions/runs/41169963144)、[Benchmarks](https://github.com/sundaysebasidian-byte/moonods/actions/runs/41169963028)。它们不是本次新增文档提交的CI结果。

## 1. 符合性声明及适用要求

MoonODS 是有界的表格数据转换库，**不声明完整ODF 1.3/XML标准认证**。数据接口子集并不免除XML/命名空间/xml:id处理义务，已解释的值和结构必须符合对应语义；资源预算和有限binary64也不是ODF有效性规则。

| 条款 | 当前实现及限制 |
|---|---|
| Part2 §2.4(A) | 包与扩展包的有界结构处理；安全附加部件可读取，不完整解释或保留全部部件语义 |
| Part2 §2.4(B.1–B.3)、Part3 §2.4(E.1–E.3) | 非验证XML处理器相关能力、Namespaces及xml:id；Unicode名称、UTF-8/UTF-16、内部DTD/实体/默认属性、非致命xml:id报告。外部依赖不联网获取，需要其内容时明确拒绝；不是全规范证明 |
| Part3 §2.4(A/C/D) | 支持范围内按类型值、坐标、合并、公式文本/缓存解释；不完整解释宏、图片、图表或任意富文本；D项的SHOULD不误写为所有扩展语义必须实现 |
| Part2/3 §2.3.1(A/B) | 特定输出经官方RNG、ZIP与独立语义核对；当前writer的实现定义范围见[完整审计](IMPLEMENTATION_DEFINED.zh-CN.md)及[逐条定位](implementation-defined_条款分类.csv)。这不是全部SHALL证明 |
| Part3 §2.4(B) | 单XML/FODS为可选能力，本产品不支持；不将其误列为通用强制要求 |

实施定义审计检索官方四部分正文，保留不同条款的相同文字，共123处定位（含术语、义务、目录，不是123项功能）。默认视图、求值HOST-LOCALE、未指定wrap及地区显示单独说明；未输出的图表/表单/加密等机制逐组标记，未把“未设属性”一概当不适用。

## 2. 合法但超出支持范围的输入

默认导入拒绝；必须显式 `allow_formatting_loss=true`（CLI `ODS_ACCEPT_LOSS=1`）。基础格式和扩展类型另有独立选项；接受损失不会跳过错误或安全检查。

| 情况 | 行为 | 修改/导出限制 |
|---|---|---|
| 合法非有限double词法INF/-INF/NaN | 模型仅支持有限数，接受损失仍拒绝，诊断为unsupported；非法邻例另报词法错误 | 拒绝不产生新输出，不把合法超范围冒称标准非法 |
| RNG合法的12px、501mm布局 | 超出本库物理布局契约，定位报告布局损失 | 可保留支持的数据并修改导出，不声称保留该布局；相关独立回执属于182历史阶段 |
| string-value与段落显示不同 | 类型值以office:string-value为准，展示损失明确报告 | 验证显示XML，不因展示不同误判值非法；不保真显示 |
| 样式/公式缓存/附加部件 | 支持范围内保留数据、合并、公式文本及缓存，其他按诊断损失或明确拒绝 | 编辑不通用重算，缓存可能过期；CSV损失类型/公式/样式等 |

[非有限数诊断说明](../FINITE_NUMBER_DIAGNOSTICS.md)已有真实包回归；既有独立8包覆盖合法超范围、非法邻例及有限正例，7拒绝且无输出、1接受。不能把7个拒绝都称为合法输入。基础格式及损失接口见[项目README](../../README.md)。本次附带的是下述DTD正例的**保存输出**，不是上述所有输入夹具，勿混为一套数据。

## 3. 支持范围内语义、输出与失败路径

- 既有功能冻结阶段四后端每后端根包+consumer合计202/202，集成23步通过；后续基线只有README/CLI注释调整，未声称每次文档改动都重新跑四后端。
- 最终独立DTD验证：10个正例经独立展开、官方RNG、CLI数值7→8.5、类型/值/坐标对照、导出再读及CSV字节比较；3个非法负例拒绝且输入/既有输出哨兵不变。
- 另1个命名空间继承案例，Expat与库一致，展开XML/输出RNG通过，但原始输入libxml2拒绝；不计作原输入通过libxml2，保留工具差异。
- 本次公开10个完全合成保存输出，重新检查四部件、CRC及XML词汇；169份基线文件摘要核对一致。脚本和回执见[复核指南](README.md)。**本次重读保存文件不是再次执行10次CLI，结构通过也不是所有语义/显示证明。**
- 已有文件系统故障注入1正例+8故障。多输出独立rename，非整体事务；后续rename失败可能已有文件替换，须检查退出码/stderr，不把accepted当导出完成。
- 真实LibreOffice GUI公式/合并及精确布局证据分别属于170/182阶段；未做当前基线全部GUI互通，也无Microsoft Office实测。公式仅保留，不通用计算。

## 4. 保留的限制

本目录包含实现范围审计及可检查的合成保存输出。它不构成完整标准认证、全公式验证、任意Office兼容性。

官方依据：[ODF1.3 Part2](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html)、[Part3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)、[Part4](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part4-formula/OpenDocument-v1.3-os-part4-formula.html)。日期：2026-10-31 UTC。
