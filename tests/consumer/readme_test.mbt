///|
/// Keeps the README snippets compiling and correct.
fn readme_report() -> Bytes raise @ods.OdsError {
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

///|
test "README: write, read back and report losses" {
  let bytes = readme_report()
  let imported = @ods.read_ods(bytes, allow_formatting_loss=true)
  let sheet = imported.workbook().sheet(0).unwrap()
  assert_eq(sheet.get(1, 1).unwrap().value(), Number(399.88))
  assert_eq(sheet.get(2, 1).unwrap().expression(), Some("of:=[.B2]*2"))
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => d.code == "FORMULA_CACHE_NOT_RECALCULATED"),
  )
}

///|
test "README: CSV and header records" {
  let workbook = @ods.Workbook::new()
  let sheet = workbook.add_csv_sheet("导入", "name,score\r\nAda,95\r\n")
  let rows = sheet.records()
  assert_eq(rows[0].values["score"], @ods.Value::Text("95"))
  assert_eq(sheet.to_csv(), "\"name\",\"score\"\r\n\"Ada\",\"95\"\r\n")
}
