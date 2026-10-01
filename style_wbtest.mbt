///|
test "style width and covered merge cells" {
  let w = Workbook::new()
  let s = w.add_sheet("Report")
  s.set(0, 0, Cell::new(Text("Title")).styled(Header))
  s.set_column_width(1, 45)
  s.merge(0, 0, 2, 2)
  let xml = w.content_xml()
  assert_true(xml.contains("style:column-width=\"45mm\""))
  assert_true(xml.contains("table:number-rows-spanned=\"2\""))
  assert_true(xml.contains("<table:covered-table-cell/>"))
  assert_true(xml.contains("table:style-name=\"Header\""))
  assert_true(
    try {
      s.set(1, 1, Cell::new(Text("hidden")))
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      s.merge(1, 1, 2, 2)
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      s.set_column_width(0, 0)
      false
    } catch {
      Invalid(_) => true
    },
  )
}
