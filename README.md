# MoonODS

MoonBit 类型化 OpenDocument 表格生成库。业务代码建立 `Workbook → Sheet → Cell`，得到完整 `.ods` 字节；核心实现是 MoonBit，只有示例的文件写入适配器使用 Node.js。项目目前仅在本地开发，尚未公开仓库或发布 mooncakes。

适合销售汇总、教学实验和调用方提供公式缓存的离线报表。它生成 ODS，不读取或转换已有文件。生态里已有 [markitdown-mb](https://github.com/ZSeanYves/markitdown) 的 ODS→Markdown 读取，以及 [mbtexcel](https://github.com/moonbitlang/office.mbt) 的 XLSX 读写；本项目聚焦有界、类型化、确定性的 ODF 1.3 writer。当前检索不等于证明生态里绝无同类项目，正式申报前需要再核查。

## 支持和边界

| 支持 | 明确不支持 |
|---|---|
| 中文、XML 转义、空格/制表/换行、空字符串及空值 | ODS 读取、ODS↔其他格式转换 |
| 有限 `Double`、布尔、Gregorian 日期（年月日） | 货币类型、时区/时间戳、任意精度十进制 |
| `of:=` 公式文本及 string/number/bool/date 缓存 | 公式语法验证、求值、重算或依赖图 |
| 多表、五种基础样式、整数毫米列宽、矩形合并 | 图表、图片、任意样式、冻结窗格、条件格式 |
| ODF 1.3 content/styles/manifest、固定 STORED ZIP | 宏、脚本、外部数据源连接、加密/签名、ZIP64 |

公式文本按调用方给出的内容保存；只检查前缀、长度和 XML 字符，不解释函数。缓存由调用方负责，办公软件可能重算，库不会修正错误缓存。请只向办公软件交付可信公式；本库不承诺拦截公式中的外部引用。数字使用 IEEE-754 `Double`，不适合要求精确十进制金额运算的计算层。

MVP 验证范围为 JS 后端。核心没有 FFI；其他后端及 LibreOffice、Excel、Numbers、WPS 的真实打开/布局/重算尚未实测。schema 与独立读取器通过不等于全部办公软件兼容。完整状态见 [中文验收矩阵](docs/ACCEPTANCE_ZH.md)。

## 安装与运行

需已有 MoonBit 工具链：`moonc v0.10.14+7d59c7ec9`、`moon 0.1.20260920 (914d7da)`，以及本次实测 Node `24.18.0`。版本与源码依赖摘要见 [TOOLCHAIN.lock](TOOLCHAIN.lock) 和 [DEPENDENCIES.lock.json](DEPENDENCIES.lock.json)。验收命令遇到版本漂移会失败，不会自动安装新工具。

在此目录运行（先把可信现有 SDK 的 bin 加入本次 shell 的 PATH，并设置该 SDK 的 MOON_HOME）：

```sh
moon check --target js -j 1 --deny-warn
moon build --target js -j 1 --deny-warn
moon test --target js -j 1 --deny-warn
moon run --target js -j 1 examples/generate
```

新检出需要解析 `moon.mod` 的固定依赖：`moon update`。源码包附带原封不动的 zipc/flate 源码归档，可用 `python3 scripts/restore_deps.py` 恢复到本项目 `.mooncakes`，再用 `scripts/verify_deps.py` 校验；这两个脚本只写本项目，不配置全局工具链。Moon 首次依赖解析仍可能需要 registry 索引/缓存；离线时应使用已准备的 SDK 缓存，不能把有网环境成功误称完全离线初始化成功。

在其他同一 workspace 的 MoonBit 包中使用：

```mbt
// moon.pkg
import { "sundaysebasidian-byte/moonods" @ods }
```

```mbt
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

Workbook/Sheet/Cell 为不透明类型，不能访问内部数组/Map绕过验证。返回的 `Bytes` 由调用方写入文件。坐标从 0 开始；`Sheet::get` 返回稀疏显式单元格的 `Cell?`，未设置格返回 None，显式空值使用 `Cell::new(Empty)`。`Cell::value` / `expression` 可取值与公式，`Workbook::content_xml` 供诊断，`to_ods` 返回包。可恢复错误为 `@ods.Invalid(message)`，详见实际编译的 [下游 API 测试](tests/consumer/api_test.mbt)。

## 三个可运行场景

`examples/generate/main.mbt` 一次生成以下合成数据，来源无个人信息：

| 文件 | 输入与用途 | 独立核值要点 |
|---|---|---|
| `sales.ods` | 中文产品/月度汇总，合并标题、表头、日期、金额、列宽 | 销量 20、金额 399.88；Decimal2 仅显示样式 |
| `experiment.ods` | “样本”“元数据”两表，测量数值、布尔标志与长备注 | -0.125、true/false、空值≠空字符串、中文空白和 emoji |
| `formulas.ods` | 数值、布尔、字符串、日期公式及调用方缓存 | `SUM` 缓存 30；其余类型缓存按输入保留，不声称求值正确 |

额外 `edge.ods` 覆盖 XML 特殊字符、长文边界、极大/极小有限数、日期端点和空表。

## 资源上限与错误

| 限制 | 当前政策 |
|---|---|
| 工作表 | 最多 32；名称 1..31 UTF-16 单位，非空白；不允许 `[]:*?/\\`、控制字符、首尾单引号；忽略大小写查重 |
| 单元格索引 | 行 0..1023、列 0..127；每表实际渲染矩形≤65,536 格，工作簿合计≤262,144 格 |
| 字符串/公式 | 每段≤32,768 UTF-16 单位；每表文本与公式合计≤2,097,152，工作簿合计≤4,194,304 |
| 合并/列宽 | 每表≤256 合并；矩形至少两格，不越界、不重叠、不覆盖显式已写值（即使 Empty）；列宽 1..500 mm |
| 序列化 | content.xml UTF-8≤16 MiB，完整包≤32 MiB；任一预算可先触发。不是进程 RSS 限制 |

表名政策为本项目互操作性约束，比 ODF 的 `string` 更严格。修改单元格/列宽/合并先验证再改变状态；失败后已写内容仍可复用。不能写入合并覆盖格；合并扩展后的矩形也计入预算。工作簿总预算在输出前预检，XML 转义膨胀在逐片写入时再限制。库在内存中构造整个包，不提供流式大型表格输出。

## 可复现验证

独立验证使用现有 Python 3.13.14 与 `odfpy 1.4.1 / lxml 6.0.2 / defusedxml 0.7.1`；它们仅用于测试。需要准备依赖的用户可在自己的虚拟环境使用 `requirements-verify.txt`。本次续做未安装新软件。

```sh
# 使用已有含上述依赖的 Python，不必与系统 python3 相同
python scripts/fetch_schemas.py
python scripts/acceptance.py --moon /absolute/path/to/existing/sdk/bin/moon
```

脚本串行运行 check/build/test、两个独立生成进程的字节比较，再用 Python zipfile、odfpy、OASIS RNG 检查包。schema 原文件从官方取得并核 SHA256，保留上游版权，未纳入 MIT 源码许可。[证据](evidence/2026-10-01-final/acceptance.json) 记录实际版本、命令、退出码、未测项，stdout/stderr 也随包保留。

`.github/workflows/ci.yml` 已提供相同检查及证据保存。它只在未来获准建立远端后运行；远端 CI、Ubuntu SDK 安装与网络依赖解析本次未测。

## 设计与合规

规范依据：[ODF 1.3 Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html) §3.2–3.3；[XML Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html) §9.1、§19.389、§19.646。mimetype 第一项、STORED、无 extra，manifest 精确列出固定 content/styles 路径，不列自身或 mimetype；固定 1980-01-01 时间戳、无随机属性、网格与列宽按顺序输出。确定性基于相同数据、样式、工作表插入顺序和锁定工具链。

zipc 的 Archive 按路径排序，会把 META-INF 放在 mimetype 前，因此本库编写小型固定路径 ZIP32 STORED 封装，复用 zipc 的 CRC32 实现；没有通用 ZIP writer/reader 或用户资产路径入口。依赖源码与摘要真实核对，归档保持上游 Apache-2.0 许可，项目原创代码为 MIT。详见 [来源](SOURCES.md)、[第三方声明](THIRD_PARTY_NOTICES.md)、[AI_USAGE](AI_USAGE.md)。

[申报参考](docs/PROPOSAL_REFERENCE.md) 是 AI 辅助技术事实，不能冒充人工最终申报书。用户需理解并人工撰写；公开仓库、mooncakes 发布、报名及身份/银行/学籍/诚信材料仍待用户处理。
