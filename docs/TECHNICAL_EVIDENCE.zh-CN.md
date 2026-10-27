# MoonODS 技术证据索引

核对日期：2026-10-27。当前安装版 **0.4.0**。

| 项目 | 内容与证据 |
| --- | --- |
| 旧基线 | 0.2.0 以写出为主；0.3.x 增加有界 ZIP/XML 读取、显式损失诊断、CSV 和表头记录。 |
| 本期贡献 | 0.4.0 新增四种显式值、基础格式读取与兼容结构处理，并在写出前检查往返预算。采购示例可从修改 CSV 重算固定模板并生成 ODS、CSV、审计记录。 |
| 当前安装版 | `moon add sundaysebasidian-byte/moonods@0.4.0`；[官方包](https://mooncakes.io/docs/sundaysebasidian-byte/moonods@0.4.0/)、[发布提交 4413e1a](https://github.com/sundaysebasidian-byte/moonods/commit/4413e1a873d1c0513fe94909a53662b51086137e)、[版本 PR #9](https://github.com/sundaysebasidian-byte/moonods/pull/9)。 |
| 复现 | [README](../README.md) 给出读改写和采购修正命令；[独立消费者](../tests/consumer)、[迁移说明](release-0.4.0.zh-CN.md)、[数据流程矩阵](DATA_WORKFLOW_SUPPORT.zh-CN.md)给出接口与验证范围。 |
| 精确版本 CI | 最终 head e567857：[核心](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40538650816)、[fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40538650789)；合并提交 4413e1a：[核心](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40539129813)、[fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40539129880)。 |

## 发布与独立消费

0.4.0 的官方 CLI 发布退出码为 0，HTTP 200，registry 构建成功。ZIP SHA256：`f29d494c247a80c64c08d8c44d415825a1e8fd5f03abff79325a4b7d4df75c28`；71 个文件与发布源码和实际安装包一致。[PR #9](https://github.com/sundaysebasidian-byte/moonods/pull/9)包含正式回执。

干净消费者从 registry 精确安装 0.4.0，无 workspace/path 覆盖，实际运行 JS、Wasm、Wasm GC、native，检查十种 Value、扩展类型显式启用、Header 样式、列宽、CSV 策略和 ODS 往返。JS 另对未修改的官方 LibreOffice/core 样本核对 B2–B5 类型和值，再导出读回。

项目合成 FODS 经 LibreOfficeDev 转换的兼容样本，与官方固定样本分开记录。候选阶段的 LibreOffice 25.2.3.2 闭环没有在此次发布轮重跑；Office 回存时间戳偏移会损失。来源与摘要见[来源说明](../SOURCES.md)、[兼容说明](READER_COMPAT.zh-CN.md)。

## 使用范围

默认拒绝有损读取；显式接受格式损失后默认按数据读取。基础格式保留、扩展类型和 CSV 扩展文本分别由独立选项启用。金额为 binary64，不是精确十进制金融计算；采购示例只重算已知模板公式。没有通用公式引擎、宏、加密、大文件流式或 Excel/打印外观保证。

README 的旧基准表仍对应 [40287799404](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40287799404/job/121455479461)，Intel Xeon Platinum 8573C、4 个逻辑 CPU、moonc 0.10.15；不改原数值，也不当作 0.4.0 测量。0.4.0 的[基准运行](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40539129794)另列。

完整旧索引保留于[历史归档](development-history/TECHNICAL_EVIDENCE-through-2026-10-27.md)，其中旧安装版和待执行措辞只描述当时状态。许可与辅助工具见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)、[AI_USAGE](../AI_USAGE.md)。
