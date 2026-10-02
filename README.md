# MoonODS

MoonBit 类型化 OpenDocument 表格生成库。业务代码建立 `Workbook → Sheet → Cell`，得到完整 `.ods` 字节；核心实现是 MoonBit，只有示例的文件写入适配器使用 Node.js。已公开 [GitHub](https://github.com/sundaysebasidian-byte/moonods) 并首发 Mooncakes `0.1.0`，MIT。真实 CI、空注册表消费和限制见 [发行记录](docs/RELEASE_ZH.md)。

**本工作目录是未发布、未推送的 0.2.0 本地候选。** 新增事务性整行写入 `Sheet::set_row`、日期公式缓存默认 DateISO，以及更严格的独立 ZIP/运行环境检查。Mooncakes 仍为 0.1.0；历史远端 CI 与注册表通过不能证明本候选已经发布或通过远端检查。当前候选的安装复现、30+5 测试和真实 LibreOfficeDev 读取见[本轮记录](docs/LOCAL_CANDIDATE_ZH.md)。

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

MVP 验证范围为 JS 后端。核心没有 FFI。现有 Mac Excel 16.113.3 已实际打开四个自制 ODS，20 组常规断言通过，整体兼容状态 **PARTIAL**：公元 0001 年显示异常，绝对毫米列宽校准未完成；本轮仅核对旧输入摘要，未重开 Excel。已装 LibreOfficeDev 26.8.0.0.alpha0 的真实无界面 Calc 导入/原生 ODS 回存核验：8 文件、33 类型值及2合并断言通过，整体仍为 **PARTIAL**，没有 GUI、打印物理列宽或稳定版本实测。Numbers、WPS、其他后端未测；schema 与独立读取器通过不等于全部办公软件兼容。详见[实测边界](docs/OFFICE_COMPATIBILITY_ZH.md)和[中文验收矩阵](docs/ACCEPTANCE_ZH.md)。

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

Mooncakes 发行版的下游依赖声明为 `sundaysebasidian-byte/moonods@0.1.0`。在自己的模块运行：

```sh
moon add sundaysebasidian-byte/moonods@0.1.0
moon check --target js -j 1
```

上述注册表命令只安装既有 0.1.0，不包含 `set_row` 或本轮日期缓存默认样式修复。要使用本地 0.2.0，使用候选源码 ZIP 与 `moon.work`；消费模块的 `moon.mod` 写 `sundaysebasidian-byte/moonods@0.2.0`，workspace 中放候选源码及独立消费模块。**不要尝试从 Mooncakes 安装 0.2.0，本轮未发布。** 自动复现用后述 `acceptance.py`，包含实际 `moon package` 后换目录消费。

源码、开发验证脚本和完整证据请从 [GitHub](https://github.com/sundaysebasidian-byte/moonods) 获取；Mooncakes 包只包含库、示例、接口、许可和说明。注册表消费结果单独记录，不用本地 workspace 成功代替。

本地独立模块消费已实际验证：`scripts/verify_reuse.py`用`moon package`候选ZIP建立新目录，独立模块与解压候选组成`moon.work`，第三方依赖从现有可信缓存解析；该本地阶段未从Mooncakes安装。之后首发0.1.0已在空注册表缓存验证，41文件与首发候选相同、4项消费测试和30类型值/9XML通过，见发行记录。手工本地workspace布局示意：

```text
moon.work                         members = ["candidate", "consumer"]
candidate/moon.mod                从moon package ZIP解压
consumer/moon.mod                 import { "sundaysebasidian-byte/moonods@0.2.0" }
consumer/src/moon.pkg             import { "sundaysebasidian-byte/moonods" @ods }
```

在消费模块的 MoonBit 包中使用：

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

Workbook/Sheet/Cell 为不透明类型，不能访问内部数组/Map绕过验证。返回的 `Bytes` 由调用方写入文件。坐标从 0 开始；`Sheet::get` 返回稀疏显式单元格的 `Cell?`，未设置格返回 None，显式空值使用 `Cell::new(Empty)`。`Cell::value` / `expression` 可取值与公式，`Workbook::content_xml` 供诊断，`to_ods` 返回包。可恢复错误为 `@ods.Invalid(message)`，详见实际编译的 [公共 API 测试包](tests/consumer/api_test.mbt)（同一模块）与[独立消费模块](fixtures/reuse-consumer/src/main.mbt)（不同模块，本地候选消费）。

0.2.0 候选支持一次写入连续的类型化行：

```mbt
sheet.set_row(3, 0, [
  @ods.Cell::new(Text("合计")).styled(Highlight),
  @ods.Cell::new(Number(20.0)),
  @ods.Cell::new(Number(399.88)).styled(Decimal2),
])
```

整批先检查坐标、合并覆盖格、渲染矩形和替换后的净文本预算，再改变任何单元格；后面的格冲突不会留下前面已写半行。空数组在有效坐标处不操作、不扩大表；无效坐标仍报错。它不是数据库事务或跨行事务。`set` 复用同一校验。调用方需先构造全部 Cell，构造非法数字/日期失败时不会调用写入。日期公式缓存现在默认 DateISO，避免 Calc 原生回存成无日期样式的数值；`.styled(...)` 仍可显式覆盖，这不是完整公式求值或跨软件保证。

`Cell::new(Date(...))` 验证 ODF 公历日期 1..9999；它不推断读取软件的日期系统。需要遵守 Excel **1900 日期系统**边界时，可显式使用 `Cell::excel_1900_date(y, m, d)`：拒绝1900-01-01以前及无效公历日，返回带DateISO样式的日期；也拒绝Excel历史上的虚构1900-02-29。此入口不配置阅读器，不承诺1904日期系统或所有Office都兼容。公式缓存可取该Cell的`.value()`后传给`Cell::formula`。

历史日期只需跨软件显示时，调用方可显式选择`Cell::new(Text("0001-01-01"))`；此值是字符串，不能参与日期运算。库不会偷偷把Date转成Text。列宽API保证写入请求的ODF整数毫米固定长度，不保证每个阅读器的屏幕像素或打印物理毫米；不按未经校准的Excel返回值缩放标准XML。

## 三个可运行场景

`examples/generate/main.mbt` 一次生成以下合成数据，来源无个人信息：

| 文件 | 输入与用途 | 独立核值要点 |
|---|---|---|
| `sales.ods` | 中文产品/月度汇总，合并标题、表头、日期、金额、列宽 | 销量 20、金额 399.88；Decimal2 仅显示样式 |
| `experiment.ods` | “样本”“元数据”两表，测量数值、布尔标志与长备注 | -0.125、true/false、空值≠空字符串、中文空白和 emoji |
| `formulas.ods` | 数值、布尔、字符串、日期公式及调用方缓存 | `SUM` 缓存 30；其余类型缓存按输入保留，不声称求值正确 |

另有[独立模块的三场景完整输入→API→输出→断言](docs/REUSE_REVIEW_ZH.md)，当前销售/实验适配器真实使用 `set_row`，从本地 0.2.0 候选包消费，实际核对30个类型值和9 XML。

额外 `edge.ods` 覆盖 XML 特殊字符、长文边界、极大/极小有限数、日期端点和空表。

日期/单位边界诊断例：`moon run --target js -j 1 examples/compatibility`，生成`examples/compatibility/generated/compatibility.ods`。展示ODF历史Date、显式Text替代、可选1900策略日期/公式缓存、1/32/500mm属性。它用于理解边界，不是已通过Excel布局验证的报表；新增文件未做原生Office实读。

## 资源上限与错误

| 限制 | 当前政策 |
|---|---|
| 工作表 | 最多 32；名称 1..31 UTF-16 单位，非空白；不允许 `[]:*?/\\`、控制字符、首尾单引号；忽略大小写查重 |
| 单元格索引 | 行 0..1023、列 0..127；每表实际渲染矩形≤65,536 格，工作簿合计≤262,144 格 |
| 字符串/公式 | 每段≤32,767 UTF-16 单位；每表文本与公式合计≤2,097,152，工作簿合计≤4,194,304 |
| 合并/列宽 | 每表≤256 合并；矩形至少两格，不越界、不重叠、不覆盖显式已写值（即使 Empty）；列宽 1..500 mm |
| 序列化 | content.xml UTF-8≤16 MiB，完整包≤32 MiB；任一预算可先触发。不是进程 RSS 限制 |

表名政策为本项目互操作性约束，比 ODF 的 `string` 更严格。Excel 实测会截断旧 32,768 字样本，故每段上限收紧至 32,767 UTF-16 单元；修改后的边界样本已完整读取。日期支持 ODF 有效公历年份 1..9999，不保证 Excel 支持全部范围；完整年月日显示可选 DateISO。修改单元格/列宽/合并先验证再改变状态；失败后已写内容仍可复用。不能写入合并覆盖格；合并扩展后的矩形也计入预算。工作簿总预算在输出前预检，XML 转义膨胀在逐片写入时再限制。库在内存中构造整个包，不提供流式大型表格输出。

## 可复现验证

独立验证使用现有 Python 3.13.14 与 `odfpy 1.4.1 / lxml 6.0.2 / defusedxml 0.7.1`；它们仅用于测试。需要准备依赖的用户可在自己的虚拟环境使用 `requirements-verify.txt`。本次续做未安装新软件。

```sh
# 使用已有含上述依赖的 Python，不必与系统 python3 相同
python scripts/fetch_schemas.py
python scripts/acceptance.py --moon /absolute/path/to/existing/sdk/bin/moon
# 上述验收也执行独立模块候选消费；单独复核可用：
python scripts/verify_reuse.py --moon /absolute/path/to/existing/sdk/bin/moon
```

脚本串行运行 check/build/test、两个独立生成进程的字节比较，再用 Python zipfile、odfpy、OASIS RNG 检查包；也运行日期/单位诊断例及独立7类型值/3 XML检查。schema 原文件从官方取得并核 SHA256，保留上游版权，未纳入 MIT 源码许可。[本候选完整证据](evidence/overnight-2026-10-02/final/acceptance.json) 记录实际版本、命令、退出码、未测项，stdout/stderr也保留。新增 ZIP 本地/中央头、EOCD/尾部一致性和15个包负控制；运行环境漂移及用新候选冒充旧注册表发行均应被拒绝，CLI 负控制保留预期退出1。本候选30核心/API与5独立消费；不把重复运行累计成不同测试。

Excel及LibreOffice是单独的应用验证，不由该跨平台脚本或远端CI执行。Excel原记录在[Excel报告](evidence/office-2026-10-01-fixed/excel.json)，当前四个源输入摘要仍相同。已装 LibreOffice 必须显式传入精确工具路径，并使用临时 profile，示意：

```sh
python scripts/verify_libreoffice.py \
  --soffice /absolute/path/to/existing/soffice \
  --reuse-input evidence/overnight-2026-10-02/final/reuse \
  --output evidence/libreoffice-local
```

此命令只导入本项目固定无宏合成 ODS，原生回存到另一目录，再由 odfpy 核值；不安装工具，不修改输入。当前实测为 Codex 运行环境已带的 LibreOfficeDev，而非下载稳定版；读取不等同于 GUI/打印验收。需要已有字体配置的机器可显式传 `--fontconfig`，不会更改全局字体。历史0.1.0注册表消费脚本使用单独冻结fixture，拒绝拿0.2.0候选报告证明0.1.0已经安装。

`.github/workflows/ci.yml` 已提供相同检查及证据保存。首发源码提交 `6dced9ed5798a7179d5259bde95145cc994f85df` 的真实远端CI通过，25核心/API和4独立消费测试均通过；运行链接与交付最新提交的CI记录见发行记录。

## 设计与合规

规范依据：[ODF 1.3 Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html) §3.2–3.3；[XML Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html) §9.1、§19.389、§19.646。mimetype 第一项、STORED、无 extra，manifest 精确列出固定 content/styles 路径，不列自身或 mimetype；固定 1980-01-01 时间戳、无随机属性、网格与列宽按顺序输出。确定性基于相同数据、样式、工作表插入顺序和锁定工具链。

zipc 的 Archive 按路径排序，会把 META-INF 放在 mimetype 前，因此本库编写小型固定路径 ZIP32 STORED 封装，复用 zipc 的 CRC32 实现；没有通用 ZIP writer/reader 或用户资产路径入口。依赖源码与摘要真实核对，归档保持上游 Apache-2.0 许可，项目原创代码为 MIT。详见 [来源](SOURCES.md)、[第三方声明](THIRD_PARTY_NOTICES.md)、[AI_USAGE](AI_USAGE.md)。

[申报参考](docs/PROPOSAL_REFERENCE.md) 是 AI 辅助技术事实，不能冒充人工最终申报书。用户需理解并人工撰写；公开仓库与包首发已获批准；报名及身份/银行/学籍/诚信材料仍由用户处理。

本轮边界补充已完成统一技术复核，按真实工程阶段提交并生成新源码交付。Library历史v2对应`dc59462`的22项测试快照；本轮为25项测试及新增诊断例。公开、首发及远端CI的最新状态见发行记录；人工申报仍由用户完成，不把工程验证称为官方验收。

以上25项/发行段落描述历史0.1.0阶段。2026-10-02本地0.2.0候选新增30+5及真实LibreOfficeDev导入证据；其源码与已发布0.1.0不同，尚未推送、发布或申报。历史提交、失败日志及Library旧版本保留，详见本轮记录。
