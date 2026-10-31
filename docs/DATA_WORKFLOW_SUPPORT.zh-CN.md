> 本页矩阵保留历史发行验证；当前源码运行锁与能力以根README为准。

# 数据型 ODS 交付验收矩阵

0.4.0 的数据流程能力与边界；[类型与格式契约](EXTENDED_VALUES_DRAFT.zh-CN.md)列出选项，[版本说明](release-0.4.0.zh-CN.md)列出迁移及发布验收。

PASS 指已有对应配置的执行结果。下表区分此前源码/Office 实验和 0.4.0 正式安装验证。

| 项目 | 状态 | 已验证范围/剩余工作 |
| --- | --- | --- |
| 数据模型 | PASS | Text/Empty/Number/Boolean/公历 Date、合并及公式文本/缓存；CSV/records 和已有 API 回归。 |
| LibreOffice 转换文件闭环 | PASS | 项目合成 FODS 经 LibreOfficeDev 转换的固定 ODS，Types(1,0) 7.5→8.5，其他值/类型/坐标/合并/公式缓存对比；导出 CSV/ODS、独立 Python 比较、稳定 LibreOffice 25.2.3.2 headless 回存再读。原输入摘要不变。 |
| 官方固定样本 | PASS | LibreOffice/core 固定 basic-cell-content.ods 的 B2–B5 类型/值及导出再读，来源与 SHA 见读取兼容说明；不重分发。 |
| 常见格式结构 | PASS（子集） | 嵌套 span/段落 style-name、无属性行列表头容器、带样式合并覆盖格；明确格式/表头元数据损失，恶意近邻拒绝。 |
| 原始往返反例 | PASS | 100×100数值表诊断耗尽、2×32767空格节点膨胀、1024×2000字符重复文本字节膨胀已关闭；大网格/Empty与空字符串/正负零/合并边界回归。 |
| 安全与失败保持 | PASS（有界） | 原12个 ZIP/XML控制及新的未知节点/属性、深度/文本、尾行与合并边界；CLI路径别名、输出目录/暂存失败、输入与旧输出不变。不代表并发或崩溃下的多文件事务。 |
| 输出容量契约 | PASS（有界） | 紧凑空格/相同非公式单元格，4 MiB总解压条目和原XML节点/深度预检。超出可往返配置就拒绝返回包，网格/文本上限不是每种组合的成功承诺。 |
| 诊断 | PASS | 高频损失每表每类32个细节＋明确计数汇总；列宽/行高/单元格数字格式、富文本/包部件/表头分类。总8192硬限不增加。 |
| 基础样式/列宽保真读回 | PASS（显式子集） | preserve_basic_formatting=true：按实际定义、继承和默认优先级识别五种既有预设；独立属性/数字格式比较及同值变色负例通过。精确1..500整数毫米保留；127mm通过Office闭环，40.01008mm不取整且报告损失。未知属性、循环、缺失、重复定义及未知有效组合均不猜测。 |
| percentage/currency/time/dateTime | PASS（显式类型子集） | allow_extended_types=true 后保留比例类型、金额及币种、日时间时长、时间戳字面/偏移。默认拒绝保持；高精度金额与未知时间语义拒绝。实际Office生成文件读改写回存通过，但Office不保留显式时间偏移，不能宣称该路径无损。CSV默认拒绝，显式文字策略保留可见类型标记。 |
| JS检查/构建/项目全测试 | PASS | 最终版本 JS 119/119；固定 SDK 的公开 CI 见版本 PR。此前隔离 0.10.16/0.10.17 源码回归保持原记录，依赖测试不计入项目新增测试。 |
| Wasm/Wasm GC | PASS（Mac pinned SDK） | Mac 原生 0.10.15 四后端各 119/119，最小控制及独立消费者实际运行通过。旧云工具链的控制失败仍为历史环境结果，不代表库失败。 |
| native | PASS（Mac arm64） | 现有原生 0.10.15 SDK/Apple clang 已完成 119/119 与独立消费者运行；不扩展为 Linux/Windows native 消费验证。 |
| 干净源码ZIP消费者 | PASS（此前本地） | 从实际源码包解压，只用其声明的锁定依赖，核源码版本、README API、扩展类型/格式/records及ODS→CSV和失败保护；不等于正式打包或注册表安装。 |
| 正式包/registry/精确 head CI | PASS（0.4.0） | 最终 head e567857、合并 4413e1a 的 8 个 CI run / 20 个 job 通过；正式包 71 文件与源码及安装一致。干净 registry 消费者四后端实际运行；九种 Value 分支、格式/列宽、CSV 策略、往返通过。[PR #9 正式回执](https://github.com/sundaysebasidian-byte/moonods/pull/9)。 |

## 可替换输入的实用流程

已有源码检出、配套SDK、Node时，使用 `examples/ods_tool` 的公开API示例：

```sh
ODS_INPUT=/path/to/input.ods ODS_ACCEPT_LOSS=1 \
  ODS_SET=0,1,0,8.5 ODS_CSV=/path/to/new.csv \
  ODS_OUTPUT=/path/to/new.ods moon run examples/ods_tool --target js
```

坐标从零起；仅修改选定数值，CSV导出第一张未合并表。扩展类型输入可加 `ODS_EXTENDED_TYPES=1`，已知基础格式可加 `ODS_PRESERVE_BASIC=1`；有扩展值时CSV另需 `ODS_EXTENDED_CSV_TEXT=1`。金额修改保留币种，时间值不接受数值覆盖。表头规则明确的表可用 `Sheet.records` 按字段取数据（见 `examples/table_csv`），不自动猜任意外部文件的表头。固定模板采购修正见 `examples/reconcile`；它只重算明确已知的模板公式，不是任意报表公式引擎。

与纯CSV相比，ODS闭环保留文本/数值/布尔/日期/Empty与空字符串的区别、多个表、合并以及公式文本和缓存；CSV丢失这些类型/结构，适合只需值的系统交换。没有宣称真实客户采用、财务精确计算或性能领先。

Excel、GUI/打印排版、任意富文本、宏/图表编辑、加密/ZIP64、通用公式计算、并发与崩溃恢复均无本轮支持证据。

## 复现实验入口

使用已有SDK、Node、requirements-verify.txt列明的验证依赖及已有LibreOffice，不自动安装或联网。以下命令在 0.4.0 对应源码中运行；0.3.1 不含新增能力。

```sh
moon test --target js --deny-warn . tests/consumer benchmarks
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/verify_basic_formatting.py --moon /path/to/moon --output /tmp/ods-style-check
python3 scripts/verify_extended_compat.py --moon /path/to/moon --soffice /path/to/soffice --output /tmp/ods-extended-check
```

输出目录需尚不存在，避免覆盖旧证据。当前固定 SDK 见 `TOOLCHAIN.lock`（本源码分支0.10.18；下述旧CI只代表历史），精确版本 CI 见[技术证据索引](TECHNICAL_EVIDENCE.zh-CN.md)。上表 0.10.16/0.10.17 是此前隔离源码验证，不替代此次固定 SDK 或 registry 结果；旧云控制失败保留原环境归属。
