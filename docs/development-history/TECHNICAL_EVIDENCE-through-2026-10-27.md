# 0.4.0 当前版本入口

新增类型、格式、兼容读取与迁移见[0.4.0 版本说明](release-0.4.0.zh-CN.md)及[数据流程矩阵](DATA_WORKFLOW_SUPPORT.zh-CN.md)。下文保留 **0.3.1 历史发行记录**，不作为 0.4.0 安装回执。

# MoonODS 技术证据索引

核对日期：2026-10-26。当前安装版 **0.3.1**。

| 项目 | 内容与证据 |
| --- | --- |
| 旧基线 | 0.2.0 只有写出。当前版本增加有界 ZIP/XML 读取、显式损失诊断、CSV 与表头记录。 |
| 本期贡献 | 类型化单元格与空值语义；读取时显式接受格式损失；采购数量修正示例重新计算固定模板并输出 ODS、CSV 与审计记录。[源码示例](../examples/reconcile)。 |
| 当前安装版 | `moon add sundaysebasidian-byte/moonods@0.3.1`；[官方包](https://mooncakes.io/docs/sundaysebasidian-byte/moonods@0.3.1/)、[0.3.0 发布提交 da08008](https://github.com/sundaysebasidian-byte/moonods/commit/da08008436d0e0db8cb2a932ba16f3ae491b3e13)、[版本 PR #5](https://github.com/sundaysebasidian-byte/moonods/pull/5)。 |
| 复现 | 独立消费者接口见 [tests/consumer](../tests/consumer)；源码业务示例使用 README 的生成、修正命令。完整源码验收：`python3 scripts/acceptance.py --output /new/empty/evidence`，依赖见 `requirements-verify.txt`。 |
| CI | 发布合后：[核心](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40286777708)、[fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40286777705)。文档修订前 `7ec5a6a`：[核心](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40288653203)、[fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40288653117)。 |

历史 0.3.0 发布轮官方 ZIP SHA256：`46b50fdcce2c962f6e85e2c495e85f0955d40764ac872f657da4433a8e15d112`。56 个文件与发布源码、实际 registry 安装一致，独立 JS 消费者的读写、CSV、Unicode 与拒绝路径通过。完整本机记录保留私有；不作为公开 CI 附件。

`da08008` 至 `7ec5a6a` 仅修改六个 CI、README、benchmark 文件，未改运行库及根配置，不需据此另发补丁版。现有包内 README 的条件发布措辞已过时，安装版本以官方 manifest 为准。

基准 CPU 为 **Intel Xeon Platinum 8573C，4 个逻辑 CPU**，moonc 0.10.15。[固定 job](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40287799404/job/121455479461)是 README 表格来源；性能数字保持原值。

采购示例与现有 reader 夹具是合成输入，不是外部客户采用。没有 Excel 外观、通用公式重算、大文件流式、宏或加密支持证据。来源、依赖许可及辅助工具披露见 [SOURCES](../SOURCES.md)、[THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)、[AI_USAGE](../AI_USAGE.md)。竞赛表单及个人说明由用户完成。

外部文件实测：[LibreOffice 固定夹具](LIBREOFFICE_REGISTRY_CASE.zh-CN.md)保留 0.3.0 的拒绝历史；0.3.1 对原文件的类型、值及往返通过，见该页边界。

0.3.1 修复仅涉及空 UI 条目和大段纯空白尾行的有界省略；79 项 JS 回归及未修改 LibreOffice 文件往返已在源码通过。新的 registry 安装验收与合并回执见本次版本 PR；不沿用 0.3.0 checksum 为 0.3.1 背书。
