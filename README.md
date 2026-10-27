# MoonODS

MoonBit 的数据型 ODS 读写库：类型化 `Workbook → Sheet → Cell`、有界 ZIP/XML 读取、显式损失诊断、CSV 与表头记录。适合需要把数据以 `.ods` 交给办公软件的报表和离线处理。

0.4.0 新增显式比例、货币、时长、时间戳与基础格式读取。[版本及迁移说明](docs/release-0.4.0.zh-CN.md)。安装命令：`moon add sundaysebasidian-byte/moonods@0.4.0`，在 `moon.pkg` 导入 `"sundaysebasidian-byte/moonods" @ods`。注册表包含库和示例源码，不安装命令行工具；下面的业务工作流示例需要源码检出和 Node.js。

复审入口：[技术证据索引](docs/TECHNICAL_EVIDENCE.zh-CN.md)。

## 从源码运行

需要已有的 MoonBit SDK 和 Node.js。CI 的固定版本见 [TOOLCHAIN.lock](TOOLCHAIN.lock)。

```sh
git clone https://github.com/sundaysebasidian-byte/moonods.git
cd moonods
moon update
moon test --target js
moon run examples/generate --target js
```

生成的文件位于 `examples/generated/`。无法连接注册表时，可用 `python3 scripts/restore_deps.py` 恢复仓库锁定的 flate 依赖，再执行 `moon work use .mooncakes/moonbit-community/flate`。

## 公共 API

```moonbit
fn make_report() -> Bytes raise @ods.OdsError {
  let workbook = @ods.Workbook::new()
  let sheet = workbook.add_sheet("销售")
  sheet.set(0, 0, @ods.Cell::new(Text("十月销售")).styled(Header))
  sheet.merge(0, 0, 1, 2)
  sheet.set(1, 0, @ods.Cell::new(Date(2026, 10, 1)).styled(DateISO))
  sheet.set(1, 1, @ods.Cell::new(Number(399.88)).styled(Decimal2))
  sheet.set(2, 1, @ods.Cell::formula("of:=[.B2]*2", Number(799.76)))
  sheet.set_column_width(1, 45)
  workbook.to_ods()
}
```

在消费模块的 `moon.pkg` 导入 `"sundaysebasidian-byte/moonods" @ods`。上述 API 已包含在 0.4.0 注册表包；0.3.1 不含新增类型与格式 API。公开接口见 [pkg.generated.mbti](pkg.generated.mbti)，独立模块测试见 [tests/consumer](tests/consumer)。

默认拒绝有损导入。调用 `@ods.read_ods(bytes, allow_formatting_loss=true)` 显式接受后，得到 Workbook 及带表名、行列、错误码的损失诊断；默认保留值、公式文本/缓存及合并，丢弃样式。另设 `preserve_basic_formatting=true` 可保留可识别的五种预设样式及 1..500 的整数毫米列宽；未知格式仍报告损失。扩展类型另需 `allow_extended_types=true`。CSV 按文本导入，导出时丢失公式、类型、样式及 Empty/空字符串区别。公式缓存可能过期，编辑不会自动重算。

## 读取、修改和导出

以下输入由项目合成 FODS 经 LibreOfficeDev 转换而来，来源见 [SOURCES.md](SOURCES.md)：

```sh
mkdir -p /tmp/moonods-example-output
ODS_INPUT=tests/reader-fixtures/external/libreoffice-dev-types.ods \
ODS_ACCEPT_LOSS=1 ODS_SET=0,1,0,8.5 \
ODS_OUTPUT=/tmp/moonods-example-output/edited.ods \
ODS_CSV=/tmp/moonods-example-output/details.csv \
ODS_CSV_CACHE=1 ODS_CSV_REJECT_FORMULA_TEXT=1 \
moon run examples/ods_tool --target js
```

`ODS_CSV_REJECT_FORMULA_TEXT=1` 拒绝以公式符号开头的文本；默认保留原文本语义，类型化负数不会被当作文本公式拒绝。这个选项不是办公软件沙箱。

## 采购数量修正与预算复核

先生成完全合成的三表模板，再读取订单数量修正 CSV：

```sh
mkdir -p /tmp/moonods-procurement/input /tmp/moonods-procurement/output
REPORT_OUTPUT=/tmp/moonods-procurement/input moon run examples/procurement --target js
printf '订单,数量\r\nSYN-202610-001,5\r\nSYN-202610-004,0\r\n' > /tmp/moonods-procurement/changes.csv
RECONCILE_INPUT=/tmp/moonods-procurement/input/procurement.ods \
RECONCILE_CHANGES=/tmp/moonods-procurement/changes.csv \
RECONCILE_OUTPUT=/tmp/moonods-procurement/output RECONCILE_ACCEPT_LOSS=1 \
moon run examples/reconcile --target js
```

输出 `reconciled.ods`、`details.csv`、`audit.csv`。这个样例的采购额从 80300 分变为 100650 分，研发超预算 18750 分；`audit.csv` 记录 CSV 请求修改的订单，以及未请求但缓存实际变化的订单。输入可以替换为符合相同三表契约的 ODS，订单和汇总不是程序中写死的数据。

这是固定模板的业务示例：数量 0..10000，金额以整数分计，总额不超过 2,000,000,000 分；只重算模板内已知的算术公式，遇到未知公式直接拒绝，不是通用采购系统或公式引擎。

## 测试

- 测试覆盖类型、空值、Unicode、CSV、ZIP/XML、错误输入和资源上限；仓库读取夹具来自项目合成 FODS、LibreOfficeDev 转换结果及故障变体。官方 LibreOffice/core 固定样本另行下载校验，不随仓库或发行包分发，见 [SOURCES.md](SOURCES.md)。
- CI：[ci.yml](.github/workflows/ci.yml) 在 wasm、wasm-gc、native 三个后端上跑库和消费者测试，并在 JS 上跑完整验收（示例、独立消费者、ODF schema 校验）；[fresh-clone.yml](.github/workflows/fresh-clone.yml) 用固定版和最新版 SDK 模拟新用户克隆后跑快速开始。
- 本地完整验收：`python3 scripts/acceptance.py --output /tmp/moonods-acceptance`，依赖见 `requirements-verify.txt`。
- `scripts/package_source.py` 导出干净源码 ZIP，`scripts/verify_delivery_consumer.py` 用独立模块消费它；`scripts/verify_reconcile.py` 可配合 LibreOffice 验证业务往返，参数见各脚本 `--help`。

## 性能

下表保留旧版固定运行的原始数值，不作为 0.4.0 的性能测量。0.4.0 合并提交另有[基准 CI](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40539129794)，两次运行不可混算。

`moon bench --release` 实测，每项 5 组取平均；GitHub Actions ubuntu-24.04（Intel Xeon Platinum 8573C，4 个逻辑 CPU），moonc v0.10.15。工作表 1000 行 × 5 列（文本、两位小数、日期、布尔、中文备注），带表头样式。

| 操作 | JS | native |
| --- | --- | --- |
| 构建工作簿并写出 `.ods` | 19.6 ms | 9.9 ms |
| 读取 `.ods` 为类型化 Workbook | 110 ms | 62.3 ms |
| 导出 CSV | 7.1 ms | 1.6 ms |

数字只说明数量级，换机器会变。复现：`moon bench benchmarks --target native --release`；CI 见 [bench.yml](.github/workflows/bench.yml)，本表来自[这次运行](https://github.com/sundaysebasidian-byte/moonods/actions/runs/40287799404)。

## 边界

0.4.0 增加显式货币/比例/时长/时间戳和基础格式读取，见[类型与格式契约](docs/EXTENDED_VALUES_DRAFT.zh-CN.md)及[数据流程矩阵](docs/DATA_WORKFLOW_SUPPORT.zh-CN.md)。候选阶段已完成 LibreOffice 25.2.3.2 读改写回存、值与格式属性比较；Office 回存时区偏移会丢失。0.4.0 发布轮另完成四后端 registry 消费及 JS 官方固定样本往返，见[版本 PR #9](https://github.com/sundaysebasidian-byte/moonods/pull/9)；该轮未重跑 Office。

- 支持文本、有限 Double、布尔、公历日期、空值、多表、基础样式、列宽和合并。
- 不提供宏、图表、加密、ZIP64、大文件流式处理和通用公式重算；没有针对 Excel 和打印外观做测试。
- 读取采用严格 ZIP 条目白名单。0.3.1 接受两个精确的空 UI 配置条目；纯空白尾行可有界省略并报告损失，不提高 1024 内容行预算。[LibreOffice 固定夹具](docs/LIBREOFFICE_REGISTRY_CASE.zh-CN.md)的类型、值及往返已通过；不代表任意 LibreOffice 文件兼容。
- 0.4.0 新增有限 `text:span`/段落样式、简单行列表头容器和带样式覆盖格读取，以及按有效前缀和剩余网格预算省略纯空白尾行。允许的属性、损失诊断及复现见 [读取兼容说明](docs/READER_COMPAT.zh-CN.md)及[数据流程验收矩阵](docs/DATA_WORKFLOW_SUPPORT.zh-CN.md)。
- 0.4.0 的 `to_ods` 在返回包之前检查 4 MiB 总解压条目及原 XML 深度/节点预算；网格/文本上限不保证每种组合都能序列化。检查性 `content_xml` 仍有独立 16 MiB 上限。重复损失保留每表每类前 32 个位置，其余给出精确计数汇总，仍保留 8192 条总诊断硬限制。
- 每个输出文件独立 rename，多个文件不是整体事务。
- 库核心是纯 MoonBit；示例里的文件读写使用 JS 宿主。

## 许可与来源

原创代码 MIT，压缩/CRC32 依赖 flate 为 Apache-2.0，SDK 不打包。见 [LICENSE](LICENSE)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[SOURCES.md](SOURCES.md) 与 [AI_USAGE.md](AI_USAGE.md)。
