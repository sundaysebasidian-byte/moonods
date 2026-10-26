# MoonODS

MoonBit 的数据型 ODS 读写库：类型化 `Workbook → Sheet → Cell`、有界 ZIP/XML 读取、显式损失诊断、CSV 与表头记录。适合需要把数据以 `.ods` 交给办公软件的报表和离线处理。

注册表上的 `0.2.0` 只有写出功能；读取、CSV 和采购修正流程在 `main` 源码中，尚未发布新版本，`moon add sundaysebasidian-byte/moonods@0.2.0` 取不到这些功能。

## 从源码运行

需要已有的 MoonBit SDK 和 Node.js。CI 的固定版本见 [TOOLCHAIN.lock](TOOLCHAIN.lock)。

```sh
git clone https://github.com/sundaysebasidian-byte/moonods.git
cd moonods
moon update
moon test --target js
moon run examples/generate --target js
```

生成的文件位于 `examples/generated/`。`moon update` 需要注册表连接；这不是离线安装证明。已有 SDK 的本地依赖恢复可用 `python3 scripts/restore_deps.py`，随后 `moon work use .mooncakes/moonbit-community/flate`，使用仓库锁定的原版依赖。

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

在消费模块的 `moon.pkg` 导入 `"sundaysebasidian-byte/moonods" @ods`。使用 `main` 源码时，通过 MoonBit workspace 引用它，不能用注册表旧版代替。公开接口见 [pkg.generated.mbti](pkg.generated.mbti)，独立模块测试见 [tests/consumer](tests/consumer)。

读取 `@ods.read_ods(bytes, allow_formatting_loss=true)` 得到 Workbook 和带表名、行列、错误码的损失诊断。默认拒绝有损导入；显式接受后保留值、公式文本/缓存及合并，丢弃样式。CSV 按文本导入，导出时丢失公式、类型、样式及 Empty/空字符串区别。公式缓存可能过期，编辑不会自动重算。

## 读取、修改和导出

以下输入是本项目生成的合成测试样本：

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

输出 `reconciled.ods`、`details.csv`、`audit.csv`。这个样例的采购额从 80300 分变为 100650 分，研发超预算 18750 分；审计记录 CSV 请求及未请求但缓存实际变化的订单。输入可以替换为符合相同三表契约的 ODS，订单和汇总不是程序中写死的数据。

这是固定模板业务适配器：数量 0..10000，金额必须能表示为整数分，总额不超过 2,000,000,000 分。仅计算已知模板算术的缓存，未知公式拒绝；不是通用采购系统或公式引擎。使用合成数据不证明实际用户采用或财务系统适用性。

## 验证与边界

- 项目测试覆盖类型、空值、Unicode、CSV、ZIP/XML、错误输入和资源上限；`tests/reader-fixtures` 只含项目合成样本及相应故障变体。
- `python3 scripts/verify_reconcile_source.py --output /absolute/new-directory` 运行当前源码的 JS 业务与失败保护检查，需要已有 SDK/Node。
- `python3 scripts/package_source.py --output /absolute/source.zip` 导出当前干净源码，不含 Git 历史。`verify_delivery_consumer.py` 可独立消费此 ZIP；`verify_reconcile.py` 另接收已有 SDK 与 LibreOffice 路径验证业务往返，参数见各脚本 `--help`。源码 ZIP 不是正式注册表包。
- `.github/workflows/fresh-clone.yml` 检查固定 SDK 与最新版；`ci.yml` 保留固定工具链的完整验收。以当前提交的新 CI 为准，旧私有完整树的结果不等于此公开版通过。
- 完整独立验证依赖见 `requirements-verify.txt`，入口为 `python3 scripts/acceptance.py`；它严格要求锁定版本并需要访问官方 schema/依赖来源，不自动安装工具。
- 运行时守卫继续检查版本漂移；仅适用于历史 0.1.0 发行的注册表候选守卫随旧发行夹具移出本源码树，不计入当前验证范围。
- 历史审计日志、旧打包材料、用户机器路径和 Wasm 复现产物未随此源码树公开。旧审计中记录的 Wasm/Wasm GC 工具链运行失败、native 组件缺失和正式打包工具缺件不因删除日志而改判通过。
- Excel、GUI/打印/外观、通用公式重算、并发及崩溃恢复未验证。每个输出文件独立 rename，多个文件不是整体事务。

库核心为 MoonBit；文件读写示例使用 JS 宿主。支持文本、有限 Double、布尔、公历日期、空值、多表、基础样式、列宽和合并；不提供宏、图表、加密、ZIP64 或大文件流式处理。

## 许可与来源

原创代码 MIT，压缩/CRC32 依赖 flate 为 Apache-2.0，SDK 不打包。见 [LICENSE](LICENSE)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[SOURCES.md](SOURCES.md) 与 [AI_USAGE.md](AI_USAGE.md)。
