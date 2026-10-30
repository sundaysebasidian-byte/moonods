# MoonODS

MoonBit 数据型 ODS 读写库：类型化工作簿、有界 ZIP/XML 读取、显式损失诊断、CSV 与表头记录。适合报表与离线数据处理，不是通用办公软件。

## 2026-10-30 复审修订

本分支基于公开提交 `6dcb77df291acf8b592224c7ba94ce648f395cc2`，不是新的 registry 发行版。`moon add sundaysebasidian-byte/moonods@0.4.0` **不包含本轮修改**。

新增 Unicode XML 名称、UTF-8/BOM UTF-16、内部 DTD/实体/默认属性、非致命 xml:id 赋型报告、PI/notation/未读取外部依赖通知，以及安全附加包部件、manifest 与签名 XML 处理。签名不做密码学验证；未知部件与嵌入文档不解释其语义，转换时明确报告丢失。外部 XML 资源不联网获取，必须依赖其内容的导入明确拒绝。接口与限制见 [XML处理器说明](docs/XML_PROCESSOR_API.md)。

当前不声明完整 ODF 或 XML 标准认证，也不以有限样本通过替代通用符合性证明。公式仅保存文本和缓存、检查外层前缀，不验证完整 OpenFormula，也不通用重算。

## 从本分支源码运行

使用 [TOOLCHAIN.lock](TOOLCHAIN.lock) 固定的 MoonBit 0.10.18；[项目内安装脚本](scripts/install-ci-sdk.py) 验证 SDK/core 双 SHA，不改全局配置。

```sh
python3 scripts/install-ci-sdk.py --dest "$PWD/.toolchains/ci-sdk"
export MOON_REGISTRY_API=1
export MOON_HOME="$PWD/.toolchains/ci-sdk"
export PATH="$MOON_HOME/bin:$PATH"
python3 scripts/restore_deps.py
moon update
moon test --target js
moon run examples/generate --target js
```

生成文件位于 `examples/generated/`。本分支的实际公开可用性以 GitHub 分支为准，不能用默认分支或旧版本复现新修复。

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

默认一律拒绝导入，要求显式确认接受数据型转换可能损失信息，即使输入只含支持类型也是如此。调用 `@ods.read_ods(bytes, allow_formatting_loss=true)` 显式接受后，得到 Workbook 及带表名、行列、错误码的损失诊断；默认保留值、公式文本/缓存及合并，丢弃样式。另设 `preserve_basic_formatting=true` 可保留可识别的五种预设样式、精确物理列宽及固定行高（mm/cm/in/pt/pc，0 < 长度 ≤ 500mm，最多 12 位十进制数字）；未知格式仍报告损失。扩展类型另需 `allow_extended_types=true`。CSV 按文本导入，导出时丢失公式、类型、样式及 Empty/空字符串区别。公式缓存可能过期，编辑不会自动重算。

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

输出 `reconciled.ods`、`details.csv`、`audit.csv`。请使用新的输出目录；复用目录会替换同名输出，先保留旧文件。这个样例的采购额从 80300 分变为 100650 分，研发超预算 18750 分；`audit.csv` 记录 CSV 请求修改的订单，以及未请求但缓存实际变化的订单。输入可以替换为符合相同三表契约的 ODS，订单和汇总不是程序中写死的数据。

这是固定模板的业务示例：数量 0..10000，金额以整数分计，总额不超过 2,000,000,000 分；只重算模板内已知的算术公式，遇到未知公式直接拒绝，不是通用采购系统或公式引擎。

## 验证与范围

此前处理器及包层冻结阶段根包加独立消费者四后端各 **176/176**；独立包层审查另生成31份API夹具，首批29份执行58次CLI，13份成功导入编辑再导出的包通过CRC、XML值和CSV检查。独立 native 全包542项包含额外夹具/示例，与176统计范围不同。

真实 LibreOffice 26.8.2.2 GUI 在此前170阶段完成类型、公式缓存和合并单元格闭环：修改 A1 后由 Calc 将 B1=A1*3 的缓存6重算12，库导出后再开仍保留公式和A2:B2合并。库没有计算公式。后续包层候选另读回同一Calc文件；这不是新版本再次GUI操作或所有Office兼容证明。详细版本绑定见[技术证据](docs/TECHNICAL_EVIDENCE.zh-CN.md)。

使用锁定 Node/Python 与 `requirements-verify.txt`，可运行 `python scripts/acceptance.py --output /tmp/moonods-acceptance`。源码CI配置见 [.github/workflows/ci.yml](.github/workflows/ci.yml)；配置存在不等于本轮远端CI已通过。

## 边界

- 默认拒绝有损读取，需要显式接受；基础格式与扩展类型分别显式开启。
- 仅解释根 spreadsheet 数据模型。附加部件可安全解析包结构，但嵌入文档不验证 XML、不保留语义；签名丢弃且不验签。
- 保留安全路径、CRC、条目数量、4 MiB总解压、XML深度/实体预算等资源限制；超限是实现限制，不称为标准禁止。
- 支持类型、值、公式缓存、合并及有限基础格式，不承诺图片、宏、图表、全样式、加密、ZIP64或打印保真。
- 没有 Microsoft Office 互通实测；金额使用binary64，非精确十进制金融计算。
- 每个输出文件独立rename，多文件不是整体事务；业务模板只重算已知算术关系。

## 许可与来源

原创代码 MIT；flate 依赖 Apache-2.0；SDK不打包。[LICENSE](LICENSE)、[SOURCES.md](SOURCES.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[AI_USAGE.md](AI_USAGE.md)。历史发行能力和性能数据保留在版本文档及历史技术索引，不当作当前修订的实测。

## 精确物理布局（有边界）

`set_column_width_length(col, "0.889in")` / `column_width_length(col)` 与
`set_row_height_length(row, "12.5pt")` / `row_height_length(row)` 保留经验证的原始长度单位与十进制值，避免强制换算成整数毫米造成损失。旧 `set_column_width(col, Int)` 保持兼容；新长度只有恰好为整数毫米时，旧 `column_width()` 才返回整数，否则返回 `None`。同列最后一次 setter 生效。

导入必须显式启用 `preserve_basic_formatting=true`，并仍确认 `allow_formatting_loss=true`。样式默认值和父样式先解析再决定是否可保留：固定行高不能有有效的 `use-optimal-row-height=true`；缺失行高不推测。输出固定布局显式写 optimal=false。未知属性、最小行高、相对宽度、自动适应和强制分页不假装保留。这里不是完整样式、字体、图片、对象或视觉布局保真。

长度预算属于产品范围而不是 ODF 有效性规则：例如合法但超范围的 501mm/px 不在此 API 范围。拒绝零、负数、指数、百分比、超过 12 位数字与超过 500mm 的物理长度。失败 setter 不修改工作表。导入超范围布局给出损失诊断；不将它误称为无效 ODF。

历史182布局阶段根包及消费者 JS / Wasm / WasmGC / native 各 **182/182**。独立审查另使用 31 份输入包逐一读改写并核对 Fraction 精确尺寸和输出 ODF 1.3 RNG；下游 API JS/native 各 9/9（其中 3 组为本次独立新增）。真实 Calc 产物原 `0.889in` 列宽可保留，`optimal=true` 的自动行高不误转为固定。上述结构验收不等于完整视觉保真。


## 新布局182阶段的实际GUI互通

官方LibreOffice26.8.2.2实际打开本阶段导出、另存、关闭再开，最后182再次读取Calc另存件并导出，再由GUI打开。A1修改7→8保持；原生另存XML列宽0.889in、固定行高0.2173in、optimal=false保持，独立Fraction尺寸差为0。界面以0.01in显示为0.89/0.22，不能把界面舍入读数当作底层XML精确值。对话框均取消未确认改变尺寸。该正控不证明所有视觉样式保真，仍有12条其他损失诊断。

本次GUI精确绑定182 CLI SHA `a60cad4b05d895b2df43e1b27c22b5b5050f7fd122c0a6cc0f7d7bc7039eef62`，并核对161份源码清单零差异；这与此前170阶段公式/合并GUI是两个独立回执。182阶段集成23步骤验收通过，源码hash结束逐项无差异；这是历史182回执，不代表后续189阶段的GUI或远端CI。


### Subsequent normative regression fixes

Physical length setters reject leading plus and non-XML surrounding whitespace; accepted tokens are checked against external ODF1.3 RNG cases. Paragraph raw XML whitespace collapses across spans according to Part3 section6.1.2, while explicit text:s/tab/line-break and NBSP remain. Text containing CR is represented with office:string-value numeric references rather than a conflicting display paragraph; this preserves data, not display fidelity. Historical182/GUI evidence remains historical; new validation is bound in the next private receipt.


189修订四后端根包及consumer各189/189；独立14段落首读/再读28次CLI与18份真实API导出RNG通过。`+1mm`拒绝，`.5mm`、`1.mm`和合法前导零按外部schema保留；只trim XML空白，不接受NBSP/EM SPACE等包围长度。CR数据属性路径已用独立负控确认：改/删属性或加入冲突段落均被验收拒绝。普通Text显式控制与NBSP保留。旧GUI测试不外推此新CR表示。

最终189集成严格23步骤全部通过，结束后全部源码/脚本哈希与运行起点一致。此运行使用固定SDK和锁定依赖；新GUI及远端CI未在该验收中运行。原错误oracle和环境依赖失败记录与修后结果分别保存，不覆盖历史。

## Typed lexical normalization

The importer applies XML Schema / RNG token whitespace collapse at typed boundaries using only XML SPACE/TAB/CR/LF. It does not use Unicode trim: NBSP and other non-XML whitespace remain significant and invalid in numeric/token values. Numeric values (including percentages and currency), boolean tokens, supported date/time values, and the value-type token are normalized before their existing lexical/range checks. Precision diagnostics compare normalized decimal identities; finite-number, underflow, and monetary exactness safeguards remain in force.

Repeat/span positiveInteger values accept a single leading `+` and surrounding XML whitespace. Date components still use the strict digit-only parser after whole-date normalization, so `2026-+10-30` remains invalid. `text:s` uses a separate nonNegativeInteger parser, allowing zero (including lexical `-0`), while repeated rows/columns/spans remain strictly positive. Resource limits are unchanged. Physical length strings still reject a leading `+` because ODF positiveLength uses a different lexical definition.

Boolean import follows the ODF RNG token values `true` and `false`; the former nonstandard `1`/`0` compatibility acceptance is intentionally removed. `office:string-value` and ordinary strings are not collapsed by this typed normalization.
