///|
test "downstream package can build a styled formula workbook" {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("客户")
  s.set(0, 0, @ods.Cell::new(Text("中文<&>")))
  s.set(0, 1, @ods.Cell::formula("of:=1+1", Number(2.0)).styled(Decimal2))
  s.set_column_width(1, 40)
  s.merge(1, 0, 1, 2)
  assert_eq(w.sheet_count(), 1)
  assert_eq(s.name(), "客户")
  let c = s.get(0, 1).unwrap()
  assert_true(c.value() is Number(2.0))
  assert_eq(c.expression(), Some("of:=1+1"))
  assert_true(w.to_ods().length() > 1000)
  assert_true(w.content_xml().contains("table:formula"))
}

///|
test "public recoverable error leaves downstream workbook unchanged" {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("a")
  s.set(0, 0, @ods.Cell::new(Boolean(false)))
  let before = w.to_ods()
  assert_true(
    try {
      s.set(-1, 0, @ods.Cell::new(Empty))
      false
    } catch {
      @ods.Invalid(_) => true
    },
  )
  assert_eq(w.to_ods(), before)
}
