// Diagnostic fixture: explicit date policy and ODF lengths, not print calibration.

///|
extern "js" fn write_file(path : String, bytes : Bytes) =
  #| (path, bytes) => { const fs = require('node:fs'); fs.mkdirSync('examples/compatibility/generated', { recursive: true }); fs.writeFileSync(path, bytes); }

///|
fn main raise {
  let w = @ods.Workbook::new()
  let dates = w.add_sheet("日期策略")
  dates.set_column_width(0, 32)
  dates.set_column_width(1, 48)
  dates.set(0, 0, @ods.Cell::new(Text("ODF 日期")).styled(Header))
  dates.set(
    0,
    1,
    @ods.Cell::new(Text("显式文本，不参与日期计算")).styled(Header),
  )
  dates.set(1, 0, @ods.Cell::new(Date(1, 1, 1)).styled(DateISO))
  dates.set(1, 1, @ods.Cell::new(Text("0001-01-01")))
  dates.set(2, 0, @ods.Cell::excel_1900_date(1900, 1, 1))
  dates.set(3, 0, @ods.Cell::excel_1900_date(9999, 12, 31))
  let cache = @ods.Cell::excel_1900_date(1900, 1, 1).value()
  dates.set(
    4,
    0,
    @ods.Cell::formula("of:=DATE(1900;1;1)", cache).styled(DateISO),
  )
  dates.set(5, 0, @ods.Cell::new(Date(1899, 12, 31)).styled(DateISO))
  dates.set(5, 1, @ods.Cell::new(Text("1899-12-31")))
  let widths = w.add_sheet("毫米属性")
  for col, mm in [1, 32, 500] {
    widths.set_column_width(col, mm)
    widths.set(0, col, @ods.Cell::new(Text("\{mm}mm 请求值")))
  }
  write_file("examples/compatibility/generated/compatibility.ods", w.to_ods())
  println("Generated date-policy and millimeter diagnostic fixture")
}
