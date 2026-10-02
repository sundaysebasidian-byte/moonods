///|
test "ODF historical dates remain dates while Excel 1900 policy rejects them" {
  for (y, m, d) in [(1, 1, 1), (1899, 12, 31)] {
    let c = Cell::new(Date(y, m, d)).styled(DateISO)
    assert_eq(c.value(), Date(y, m, d))
    assert_true(c.xml("").contains("office:value-type=\"date\""))
    assert_true(
      try {
        Cell::excel_1900_date(y, m, d) |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  assert_true(
    Cell::new(Date(1, 1, 1))
    .xml("")
    .contains("office:date-value=\"0001-01-01\""),
  )
  for (y, m, d) in [(1900, 1, 1), (2000, 2, 29), (9999, 12, 31)] {
    let c = Cell::excel_1900_date(y, m, d)
    assert_eq(c.value(), Date(y, m, d))
    assert_true(c.xml("").contains("table:style-name=\"DateISO\""))
  }
  for (y, m, d) in [(0, 1, 1), (1900, 2, 29), (10000, 1, 1)] {
    assert_true(
      try {
        Cell::excel_1900_date(y, m, d) |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  let text = Cell::new(Text("0001-01-01"))
  assert_true(text.xml("").contains("office:value-type=\"string\""))
  assert_true(!text.xml("").contains("office:date-value="))
  let cache = Cell::excel_1900_date(2026, 10, 1).value()
  assert_eq(Cell::formula("of:=DATE(2026;10;1)", cache).value(), cache)
}

///|
test "date formula cache defaults to ISO presentation with explicit override" {
  let c = Cell::formula("of:=DATE(2026;10;1)", Date(2026, 10, 1))
  assert_eq(c.value(), Date(2026, 10, 1))
  assert_true(c.xml("").contains("table:style-name=\"DateISO\""))
  assert_true(c.styled(Header).xml("").contains("table:style-name=\"Header\""))
  assert_true(
    Cell::formula("of:=1+1", Number(99.0))
    .xml("")
    .contains("table:style-name=\"Plain\""),
  )
}

///|
test "requested millimeter width mapping and rejected mutation remain exact" {
  let w = Workbook::new()
  let s = w.add_sheet("单位边界")
  s.set_column_width(0, 1)
  s.set_column_width(1, 32)
  s.set_column_width(2, 500)
  let before = w.to_ods()
  for bad in [-1, 0, 501] {
    assert_true(
      try {
        s.set_column_width(1, bad)
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_eq(w.to_ods(), before)
  }
  let xml = w.content_xml()
  for mm in [1, 32, 500] {
    assert_true(xml.contains("style:column-width=\"\{mm}mm\""))
    assert_true(
      xml.contains("<table:table-column table:style-name=\"W\{mm}\"/>"),
    )
  }
  s.set_column_width(1, 64)
  assert_true(!w.content_xml().contains("style:column-width=\"32mm\""))
  assert_true(w.content_xml().contains("style:column-width=\"64mm\""))
}
