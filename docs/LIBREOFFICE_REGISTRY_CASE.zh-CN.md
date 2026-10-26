# LibreOffice 固定夹具：0.3.0 的真实限制

2026-10-26，用 registry **MoonODS 0.3.0**、moonc **0.10.15**、JS + Node **24.18.0** 测试，无 workspace/path 覆盖。

输入为 LibreOffice/core 固定提交 `528ba1172ce7f2193db9297a3dac0bc4da7cd9d9` 的 [basic-cell-content.ods](https://github.com/LibreOffice/core/blob/528ba1172ce7f2193db9297a3dac0bc4da7cd9d9/sc/qa/unit/data/ods/basic-cell-content.ods)，10,552 字节，SHA256：

```text
634fe14c4daaf4e3e15db2dd3b72ba0deabb52d95a05d0f95764006c838ba0dc
```

[上游断言](https://github.com/LibreOffice/core/blob/528ba1172ce7f2193db9297a3dac0bc4da7cd9d9/sc/qa/unit/subsequent_filters_test.cxx#L417-L434)要求第一张表 B2 为文本 `LibreOffice Calc`、B3 为数值 `12345`、B4 为文本 `A < B`、B5 为数值 `0`。本次计划断言类型和值，再导出、再读。

**实际结果：拒绝，退出 1。** 显式 `allow_formatting_loss=true` 后仍报 `OdsError.Invalid: unsupported ODS package entry`。首个不在 ZIP 白名单内的条目是 `Configurations2/images/Bitmaps/`；另有 `Configurations2/accelerator/current.xml`。失败发生在单元格解析前，四个断言和导出再读均未执行。原文件未修改。

## 复现

只在仓库外下载上游二进制，不运行宏、外链或办公软件。本仓库不重分发夹具。上游项目为 MPL-2.0，并有历史 Apache 来源；该二进制的专用许可未单独确认，不能改标为本项目 MIT。

```sh
mkdir libreoffice-ods-consumer && cd libreoffice-ods-consumer
curl -fL https://raw.githubusercontent.com/LibreOffice/core/528ba1172ce7f2193db9297a3dac0bc4da7cd9d9/sc/qa/unit/data/ods/basic-cell-content.ods -o basic-cell-content.ods
shasum -a 256 basic-cell-content.ods
printf 'name = "local/libreoffice-ods-demo"\nversion = "0.1.0"\n' > moon.mod
moon add sundaysebasidian-byte/moonods@0.3.0
export CASE_INPUT="$PWD/basic-cell-content.ods"
export CASE_OUTPUT="$PWD/roundtrip.ods"
```

创建 `moon.pkg`：

```moonbit
import { "sundaysebasidian-byte/moonods" @ods }
options(is_main: true)
```

创建 `main.mbt`：

```moonbit
extern "js" fn input_bytes() -> Bytes =
  #| () => new Uint8Array(require('node:fs').readFileSync(process.env.CASE_INPUT))

extern "js" fn save_bytes(data : Bytes) -> Unit =
  #| data => require('node:fs').writeFileSync(process.env.CASE_OUTPUT, data)

fn check(book : @ods.Workbook) -> Unit raise {
  let sheet = book.sheet(0).unwrap()
  assert_eq(sheet.get(1, 1).unwrap().value(), @ods.Text("LibreOffice Calc"))
  assert_eq(sheet.get(2, 1).unwrap().value(), @ods.Number(12345.0))
  assert_eq(sheet.get(3, 1).unwrap().value(), @ods.Text("A < B"))
  assert_eq(sheet.get(4, 1).unwrap().value(), @ods.Number(0.0))
}

fn run_case() -> Unit raise {
  let imported = @ods.read_ods(input_bytes(), allow_formatting_loss=true)
  for d in imported.diagnostics() {
    println("loss: \{d.code} sheet=\{d.sheet} row=\{d.row} col=\{d.col}")
  }
  check(imported.workbook())
  println("PASS: upstream B2 Text, B3 Number, B4 Text, B5 Number(0)")
  let output = imported.workbook().to_ods()
  save_bytes(output)
  let again = @ods.read_ods(output, allow_formatting_loss=true)
  check(again.workbook())
  println("PASS: export and re-read preserves all four types and values")
}

extern "js" fn exit_failed() -> Unit =
  #| () => process.exit(1)

fn main {
  try { run_case() } catch {
    @ods.OdsError::Invalid(reason) => { println("FAILED: OdsError.Invalid: \{reason}"); exit_failed() }
    error => { println("FAILED: \{error}"); exit_failed() }
  }
}
```

```sh
moon run . --target js -j 1
moon tree --json  # moonods 应为 0.3.0、source.kind=registry
```

这是外部文件兼容性缺口，不是未发的库修复。本轮保留拒绝行为；后续支持这些条目仍需审查安全白名单和损失诊断，再完成原文件的类型、值及往返断言。合成夹具通过不能替代这项验证。
