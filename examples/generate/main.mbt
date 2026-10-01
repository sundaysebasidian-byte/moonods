// This example-only adapter writes bytes. The core library does not use FFI.

///|
extern "js" fn write_file(path : String, bytes : Bytes) =
  #| (path, bytes) => { const fs = require('node:fs'); fs.mkdirSync('examples/generated', { recursive: true }); fs.writeFileSync(path, bytes); }

///|
fn sales() -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("销售报表")
  s.set(
    0,
    0,
    @ods.Cell::new(Text("2026年10月销售（合成示例）")).styled(Header),
  )
  s.merge(0, 0, 1, 4)
  for col, title in ["月份", "产品", "销量", "金额"] {
    s.set(1, col, @ods.Cell::new(Text(title)).styled(Header))
  }
  s.set(2, 0, @ods.Cell::new(Date(2026, 10, 1)).styled(DateISO))
  s.set(2, 1, @ods.Cell::new(Text("月光笔 <限定>&\"版\"")))
  s.set(2, 2, @ods.Cell::new(Number(12.0)))
  s.set(2, 3, @ods.Cell::new(Number(359.88)).styled(Decimal2))
  s.set(3, 0, @ods.Cell::new(Date(2026, 10, 1)).styled(DateISO))
  s.set(3, 1, @ods.Cell::new(Text("便签")))
  s.set(3, 2, @ods.Cell::new(Number(8.0)))
  s.set(3, 3, @ods.Cell::new(Number(40.0)).styled(Decimal2))
  s.set(4, 1, @ods.Cell::new(Text("合计")).styled(Highlight))
  s.set(4, 2, @ods.Cell::new(Number(20.0)).styled(Highlight))
  s.set(4, 3, @ods.Cell::new(Number(399.88)).styled(Decimal2))
  for col, mm in [32, 64, 24, 34] {
    s.set_column_width(col, mm)
  }
  w
}

///|
fn experiment() -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("样本")
  for col, title in ["采样日期", "温度°C", "通过", "备注"] {
    s.set(0, col, @ods.Cell::new(Text(title)).styled(Header))
  }
  s.set(1, 0, @ods.Cell::new(Date(2024, 2, 29)).styled(DateISO))
  s.set(1, 1, @ods.Cell::new(Number(-0.125)).styled(Decimal2))
  s.set(1, 2, @ods.Cell::new(Boolean(true)))
  s.set(
    1,
    3,
    @ods.Cell::new(Text(" 中文  双空格\t制表\n下一行 😀 ")),
  )
  s.set(2, 0, @ods.Cell::new(Empty))
  s.set(2, 1, @ods.Cell::new(Number(0.0)))
  s.set(2, 2, @ods.Cell::new(Boolean(false)))
  s.set(2, 3, @ods.Cell::new(Text("")))
  for col, mm in [32, 30, 20, 80] {
    s.set_column_width(col, mm)
  }
  let meta = w.add_sheet("元数据")
  meta.set(0, 0, @ods.Cell::new(Text("数据来源")).styled(Header))
  meta.set(0, 1, @ods.Cell::new(Text("合成测试数据，无个人信息")))
  let b = StringBuilder()
  for _ in 0..<1000 {
    b.write_string("长文与XML<&>转义。")
  }
  meta.set(1, 0, @ods.Cell::new(Text("长备注")))
  meta.set(1, 1, @ods.Cell::new(Text(b.to_string())))
  meta.set_column_width(1, 100)
  w
}

///|
fn formulas() -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("公式缓存")
  s.set(0, 0, @ods.Cell::new(Number(10.0)))
  s.set(1, 0, @ods.Cell::new(Number(20.0)))
  s.set(
    2,
    0,
    @ods.Cell::formula("of:=SUM([.A1:.A2])", Number(30.0)).styled(Decimal2),
  )
  s.set(0, 1, @ods.Cell::formula("of:=[.A1]<[.A2]", Boolean(true)))
  s.set(
    1,
    1,
    @ods.Cell::formula("of:=\"中文 & 结果\"", Text("中文 & 结果")),
  )
  s.set(
    2,
    1,
    @ods.Cell::formula("of:=DATE(2026;10;1)", Date(2026, 10, 1)).styled(DateISO),
  )
  s.set(
    3,
    1,
    @ods.Cell::new(Text("缓存由调用方提供；办公软件可能重算")),
  )
  s.set_column_width(1, 90)
  w
}

///|
fn edge() -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("边界 & XML")
  let values : Array[@ods.Value] = [
    Text(" <&>\"'\t\n\r 😀 中文 "),
    Text(""),
    Empty,
    Number(1.0e300),
    Number(1.0e-300),
    Boolean(false),
    Date(1, 1, 1),
    Date(9999, 12, 31),
  ]
  for row, v in values {
    s.set(row, 0, @ods.Cell::new(v))
  }
  let b = StringBuilder()
  for _ in 0..<32768 {
    b.write_string("x")
  }
  s.set(8, 0, @ods.Cell::new(Text(b.to_string())))
  w.add_sheet("空表") |> ignore
  w
}

///|
fn main raise {
  write_file("examples/generated/sales.ods", sales().to_ods())
  write_file("examples/generated/experiment.ods", experiment().to_ods())
  write_file("examples/generated/formulas.ods", formulas().to_ods())
  write_file("examples/generated/edge.ods", edge().to_ods())
  println("Generated sales, experiment, formulas and edge ODS files")
}
