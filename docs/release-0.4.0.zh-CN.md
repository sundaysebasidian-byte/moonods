# MoonODS 0.4.0：类型、格式与读取兼容

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

最终实现输入的 Mac pinned SDK 0.10.15 四后端各 119/119、最小控制和独立消费者已实际运行；同步接口后的候选四后端 `moon info` 均零 diff，实际官方私有 ZIP 的消费者也运行通过。它们是本地源码/打包证据，不等于本 PR 远端 CI 或正式 registry 安装。

远端精确 head、合后 CI、官方发布 checksum 和干净 registry 安装回执在版本 PR 中记录；未执行前不宣称完成。已存在的 Office 25.2.3.2 闭环结果沿用原测试日期与范围，不写成此次重新运行；没有 Excel、GUI/打印外观、生产采用或并发事务保证。

MIT、依赖许可、来源及 AI 辅助披露分别见 `LICENSE`、`THIRD_PARTY_NOTICES.md`、`SOURCES.md` 与 `AI_USAGE.md`。外部 Office 二进制夹具不打入发行包。
