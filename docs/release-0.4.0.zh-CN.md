# MoonODS 0.4.0：类型、格式与读取兼容

发布日期：2026-10-27。安装：`moon add sundaysebasidian-byte/moonods@0.4.0`；[官方包](https://mooncakes.io/docs/sundaysebasidian-byte/moonods@0.4.0/)。

相对 0.3.1，增加 `Percentage`、`Currency`、`Duration`、`DateTime` 四个公开 `Value` 分支、`Cell.style` 与 `Sheet.column_width`。读取支持有限富文本/表头容器和基础格式子集；写出前预检往返所需的 ZIP/XML 预算，频繁损失用有界明细和精确汇总报告。

## 从 0.3.1 迁移

- 更新穷尽匹配 `Value` 的代码，为四个新分支制定明确策略；因此使用 minor 版本 0.4.0。
- 默认读取继续拒绝扩展类型。需要时显式 `allow_extended_types=true`；基础格式保留需另设 `preserve_basic_formatting=true`，不替代 `allow_formatting_loss=true`。
- CSV 默认拒绝扩展类型；显式 `extended_types_as_text=true` 才输出可见文本标记。
- 金额仍是 binary64，不是十进制金融算术；不进行通用公式重算。时间戳字面值在库内往返保留，但 Office 回存可能丢失时区偏移。仅保留可确定的预设样式和整数毫米列宽，未知格式报告损失。

## 安装与复现

安装命令：`moon add sundaysebasidian-byte/moonods@0.4.0`；实际可用版本以[Mooncakes manifest](https://mooncakes.io/api/v0/manifest/sundaysebasidian-byte/moonods@0.4.0)为准。源码消费使用声明的锁定依赖；0.3.1 包不含新增 API。

源码：`moon test --target js -j 1 --deny-warn . tests/consumer`；工具链见 `TOOLCHAIN.lock`。接口与格式复现：`moon info`、`moon fmt --check`。完整验证脚本见[数据流程矩阵](DATA_WORKFLOW_SUPPORT.zh-CN.md)。

## 验证范围

[版本 PR #9](https://github.com/sundaysebasidian-byte/moonods/pull/9)记录最终 head `e567857`、合并提交 `4413e1a`、8 个成功 CI run / 20 个 job，以及正式发布回执。官方 CLI 退出 0、HTTP 200；71 个发行文件与源码、registry 安装一致。ZIP SHA256：`f29d494c247a80c64c08d8c44d415825a1e8fd5f03abff79325a4b7d4df75c28`。

干净 registry 消费者在 JS、Wasm、Wasm GC、native 实际运行，覆盖十种 Value、扩展类型开关、Header 样式、列宽、CSV 显式策略及往返；JS 另通过未修改的官方 LibreOffice 样本 B2–B5 类型、值及导出再读。精确 CI 链接见[技术证据索引](TECHNICAL_EVIDENCE.zh-CN.md)。

实现阶段 Mac pinned SDK 0.10.15 四后端各 119/119 及接口零 diff，属于此前源码证据。Office 25.2.3.2 闭环也保持原测试日期；此次发布轮未重跑 Office。没有 Excel、GUI/打印外观、生产采用或并发事务保证。

MIT、依赖许可、来源及 AI 辅助披露分别见 `LICENSE`、`THIRD_PARTY_NOTICES.md`、`SOURCES.md` 与 `AI_USAGE.md`。外部 Office 二进制夹具不打入发行包。
