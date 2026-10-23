# MoonODS

[![CI](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/ci.yml/badge.svg)](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/ci.yml)
[![Fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/fresh-clone.yml/badge.svg)](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/fresh-clone.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

用 MoonBit 读写 OpenDocument 表格（`.ods`，LibreOffice 等办公软件使用的开放格式）：**类型化的 Workbook → Sheet → Cell 模型，输出确定、资源有上限，读取时把每一处丢失逐项报告出来。**

适合：在 MoonBit 程序里直接生成报表、导出实验数据、读取别人给的 `.ods` 做校验或改写，以及和 CSV 互转。

## 快速开始

需要 MoonBit 工具链（CI 锁定 `moonc v0.10.15+943464bfa`，见 [TOOLCHAIN.lock](TOOLCHAIN.lock)）和 Node.js。

```sh
git clone https://github.com/sundaysebasidian-byte/moonods.git
cd moonods
moon update                                   # 新装的 SDK 需要先拉取包索引
moon test                                     # 全部测试
moon run examples/generate --target js        # 生成 examples/generated/ 下 4 个 .ods
```

用 LibreOffice 打开 `examples/generated/sales.ods` 即可看到结果。

在自己的项目里使用：

```sh
moon add sundaysebasidian-byte/moonods
```

```moonbit
// moon.pkg
import { "sundaysebasidian-byte/moonods" @ods }
```

> 已发布的 0.2.0 只有写出功能；读取 `read_ods`、CSV 互转和表头记录在当前源码中，尚未发布新版本。

## 用法

### 写出

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
  workbook.to_ods() // 返回 Bytes，由调用方写文件
}
```

### 读回并查看损失

```moonbit
let imported = @ods.read_ods(bytes, allow_formatting_loss=true)
let sheet = imported.workbook().sheet(0).unwrap()
sheet.get(1, 1).unwrap().value()      // Number(399.88)
for d in imported.diagnostics() {
  println("\{d.sheet} R\{d.row}C\{d.col} \{d.code}") // 例如 FORMULA_CACHE_NOT_RECALCULATED
}
```

读取是**数据型导入**：值、公式文本和缓存、合并区域会保留，样式会丢。默认遇到会丢失的内容就拒绝，必须显式 `allow_formatting_loss=true`，每一处丢失都会有一条带表名、行列和错误码的诊断。读回的 Workbook 可以继续编辑并 `to_ods()` 写回。

### CSV 与表头记录

```moonbit
let sheet = workbook.add_csv_sheet("导入", "name,score\r\nAda,95\r\n") // RFC 4180，全部按文本导入
let rows = sheet.records()                                            // 第一行作表头，按列名取值
let csv = sheet.to_csv()                                              // 确定性 CSV，字段全部加引号，CRLF 结尾
```

本节代码都在 [tests/consumer/readme_test.mbt](tests/consumer/readme_test.mbt) 中作为测试运行。

### 三个场景

| 场景 | 位置 | 内容 |
| --- | --- | --- |
| 生成报表 | [examples/generate](examples/generate/main.mbt) | 销售汇总（合并标题、日期、金额格式、列宽）、多表实验数据、带缓存的公式，另有边界样本 |
| 读取并改写外部文件 | [examples/ods_tool](examples/ods_tool/main.mbt) | 读 LibreOffice 生成的 `.ods`，打印诊断，可改单元格、导出 CSV、写回 |
| CSV 互转 | [examples/table_csv](examples/table_csv/main.mbt) | CSV 导入为文本表，配合类型化表按表头取记录，写出 ODS 后读回核对 |

```sh
ODS_INPUT=tests/reader-fixtures/external/libreoffice-dev-types.ods ODS_ACCEPT_LOSS=1 \
  moon run examples/ods_tool --target js
```

## 支持范围

| 支持 | 不支持 |
| --- | --- |
| 文本（含中文、emoji、空白）、`Double`、布尔、公历日期、空值与空字符串区分 | 货币、时间戳 / 时区、任意精度十进制 |
| `of:=` 公式文本与 string / number / bool / date 缓存 | 公式求值与重算 |
| 多表、5 种基础样式、毫米列宽、矩形合并 | 图表、图片、条件格式、任意样式 |
| ODF 1.3 content / styles / manifest，固定时间戳的 STORED ZIP | 宏、加密 / 签名、ZIP64 |
| 读取：类型值、公式、合并；逐项损失诊断 | 读取时保留原样式；图表 / 图片 / 宏 / 加密等直接拒绝 |

所有资源都有上限（每簿 32 表、每表 1024 行 × 128 列、单段文本 32,767 UTF-16 单位、整包 32 MiB 等），超限在修改前就报错，失败不会留下写了一半的状态。读取对伪造大小的 ZIP、DTD、重复条目、过深 XML 等恶意输入有可复现的拒绝行为。

## 设计取舍

- **不透明类型**：`Workbook` / `Sheet` / `Cell` 不暴露内部数组，所有写入都经过校验。
- **确定性输出**：同样的数据和插入顺序得到逐字节相同的文件，便于测试和版本管理。
- **宁可拒绝，不静默丢弃**：读取时任何无法表达的内容要么报错，要么在显式同意后逐项记录到诊断里。
- **无 FFI**：核心是纯 MoonBit，返回 `Bytes`，文件读写由宿主负责，因此 JS 和 Wasm GC 都能用。
- 压缩与 CRC32 使用 `moonbit-community/flate`，ZIP 封装与 XML 由本库实现。

规范依据：[ODF 1.3 Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html) 与 [Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)。公开接口见 [pkg.generated.mbti](pkg.generated.mbti)。

## 测试与验证

- MoonBit 测试覆盖写出、读取、损失诊断、ZIP 与 XML 解析、恶意样本、CSV、边界值，以及同一模块的独立消费者。
- 独立校验：生成的文件用 Python zipfile、odfpy 和 OASIS 官方 RelaxNG schema 检查；两个进程分别生成并比较字节。
- 真实办公软件：LibreOffice 无界面导入与原生回存后核对值、日期格式和合并；Excel 打开过早期版本的样本。逐项结果和未覆盖项见 [docs/OFFICE_COMPATIBILITY_ZH.md](docs/OFFICE_COMPATIBILITY_ZH.md)。
- CI：[ci.yml](.github/workflows/ci.yml) 跑完整验收（JS 与 Wasm GC 测试、确定性、schema、守卫、消费者）；[fresh-clone.yml](.github/workflows/fresh-clone.yml) 模拟新用户 `git clone` 后直接 `moon test` 和本页的快速开始，并在最新 SDK 上同样跑一遍。

本地完整验收：`python scripts/acceptance.py`（依赖见 `requirements-verify.txt`）。
各轮验证的命令、版本和结果见 [docs/VERIFICATION_20261022_ZH.md](docs/VERIFICATION_20261022_ZH.md) 与 `evidence/`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `workbook.mbt` `cell.mbt` `style.mbt` | 类型化模型与校验 |
| `xml.mbt` `package.mbt` | content / styles / manifest 生成与 ZIP 封装 |
| `reader.mbt` `reader_xml.mbt` `reader_zip.mbt` | 有界读取与损失诊断 |
| `csv.mbt` `records.mbt` | CSV 互转与表头记录 |
| `examples/` | 可运行示例 |
| `tests/` | 独立消费者测试与读取样本 |

## 许可与来源

代码 MIT（[LICENSE](LICENSE)）。依赖 flate 为 Apache-2.0，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)；参考资料与生态对比见 [SOURCES.md](SOURCES.md)。
开发中 AI 的参与方式见 [AI_USAGE.md](AI_USAGE.md)，技术方案见 [docs/PROPOSAL_REFERENCE.md](docs/PROPOSAL_REFERENCE.md)。
