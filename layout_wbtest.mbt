///|
test "physical lengths retain exact tokens while legacy integer getter stays exact" {
  let book = Workbook::new()
  let s = book.add_sheet("Lengths")
  for
    col, token in [
      "0.889in", "1.3008in", "1pt", "0.5pc", "4.001008cm", "500.0mm",
    ] {
    s.set_column_width_length(col, token)
    assert_eq(s.column_width_length(col), Some(token))
  }
  assert_eq(s.column_width(0), None)
  assert_eq(s.column_width(5), Some(500))
  s.set_column_width(0, 40)
  assert_eq(s.column_width_length(0), Some("40mm"))
  assert_eq(s.column_width(0), Some(40))
  s.set_column_width_length(0, "  0.1cm  ")
  assert_eq(s.column_width(0), Some(1))
  assert_eq(s.column_width_length(0), Some("0.1cm"))
}

///|
test "physical setters reject invalid and excessive tokens without mutation" {
  let s = Workbook::new().add_sheet("Safe")
  s.set_column_width_length(0, "0.889in")
  s.set_row_height_length(0, "14pt")
  for
    token in [
      "0mm", "-1mm", "501mm", "50.01cm", "20in", "1px", "1%", "2*", "1e2mm", "NaNmm",
      "+1mm", "+.5pt", "Infinitymm", ".mm", "+mm", "1..2mm", "1 mm", "1MM", "1mm\"/><x/>",
      "0000000000001mm", "0.0000000000001mm",
    ] {
    assert_true(
      try {
        s.set_column_width_length(0, token)
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_true(
      try {
        s.set_row_height_length(0, token)
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_eq(s.column_width_length(0), Some("0.889in"))
    assert_eq(s.row_height_length(0), Some("14pt"))
  }
  assert_true(
    try {
      s.set_column_width_length(128, "1mm")
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      s.set_row_height_length(1024, "1mm")
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(s.dimensions(), (1, 1))
}

///|
test "exact layout roundtrip requires explicit basic formatting opt in" {
  let b = Workbook::new()
  let s = b.add_sheet("Layout")
  s.set(0, 0, Cell::new(Text("abc")))
  s.set_column_width_length(0, "0.889in")
  s.set_column_width_length(1, "1pt")
  s.set_row_height_length(0, "14.5pt")
  s.set_row_height_length(1, "0.5cm")
  let data = b.to_ods()
  let plain = read_ods(data, allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(plain.column_width_length(0), None)
  assert_eq(plain.row_height_length(0), None)
  let exact = read_ods(
    data,
    allow_formatting_loss=true,
    preserve_basic_formatting=true,
  )
  let back = exact.workbook().sheet(0).unwrap()
  assert_eq(back.column_width_length(0), Some("0.889in"))
  assert_eq(back.column_width_length(1), Some("1pt"))
  assert_eq(back.row_height_length(0), Some("14.5pt"))
  assert_eq(back.row_height_length(1), Some("0.5cm"))
  assert_true(exact.diagnostics().any(d => d.code == "ROW_HEIGHT_RETAINED"))
  let second = read_ods(
      exact.workbook().to_ods(),
      allow_formatting_loss=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(second.row_height_length(0), Some("14.5pt"))
  assert_eq(second.column_width_length(0), Some("0.889in"))
}

///|
test "fixed height inheritance and explicit automatic override are not guessed" {
  let base = "<style:style style:name='Parent' style:family='table-row'><style:table-row-properties style:row-height='14pt' style:use-optimal-row-height='true'/></style:style>"
  for
    (properties, expected) in [
      ("", None),
      (
        "<style:table-row-properties style:use-optimal-row-height='false'/>",
        Some("14pt"),
      ),
    ] {
    let defs = base +
      "<style:style style:name='Child' style:family='table-row' style:parent-style-name='Parent'>" +
      properties +
      "</style:style>"
    let result = format_case(
      defs, "<t:table-row t:style-name='Child' t:number-rows-repeated='2'><t:table-cell/></t:table-row>",
    )
    assert_eq(
      result.workbook().sheet(0).unwrap().row_height_length(0),
      expected,
    )
    assert_eq(
      result.workbook().sheet(0).unwrap().row_height_length(1),
      expected,
    )
  }
  for
    attr in [
      "style:use-optimal-row-height='true'", "style:min-row-height='1mm'", "fo:break-before='page'",
      "fo:keep-together='always'",
    ] {
    let defs = "<style:style style:name='R' style:family='table-row'><style:table-row-properties style:row-height='14pt' " +
      attr +
      "/></style:style>"
    let result = format_case(
      defs, "<t:table-row t:style-name='R'><t:table-cell/></t:table-row>",
    )
    assert_eq(result.workbook().sheet(0).unwrap().row_height_length(0), None)
  }
}

///|
test "row defaults inherit but cell styles and column widths remain independent" {
  let defs = "<style:default-style style:family='table-row'><style:table-row-properties style:row-height='0.7cm'/></style:default-style><style:default-style style:family='table-column'><style:table-column-properties style:column-width='1.3008in'/></style:default-style>"
  let result = format_case(defs, "<t:table-row><t:table-cell/></t:table-row>")
  let s = result.workbook().sheet(0).unwrap()
  assert_eq(s.row_height_length(0), Some("0.7cm"))
  assert_eq(s.column_width_length(0), Some("1.3008in"))
}

///|
test "layout serialization is deterministic and not style-name injection" {
  let a = Workbook::new()
  let sa = a.add_sheet("L")
  sa.set_row_height_length(1, "1.0mm")
  sa.set_row_height_length(0, "1pt")
  sa.set_column_width_length(1, "0.1cm")
  sa.set_column_width_length(0, "1pt")
  let b = Workbook::new()
  let sb = b.add_sheet("L")
  sb.set_column_width_length(0, "1pt")
  sb.set_column_width_length(1, "0.1cm")
  sb.set_row_height_length(0, "1pt")
  sb.set_row_height_length(1, "1.0mm")
  assert_eq(a.to_ods(), b.to_ods())
  assert_true(a.content_xml().contains("style:name=\"RH0_1\""))
  assert_false(a.content_xml().contains("style:name=\"+"))
}

///|
test "layout unsigned positiveLength lexical forms" {
  let w = Workbook::new()
  let s = w.add_sheet("lexical")
  for v in [".5mm", "1.mm", "0001.00mm", "0.001pt", "  1mm  "] {
    s.set_column_width_length(0, v)
    s.set_row_height_length(0, v)
  }
  let before = w.to_ods()
  for v in ["+1mm", "+.5mm", "+0001.0in"] {
    assert_true(
      try {
        s.set_column_width_length(1, v)
        false
      } catch {
        _ => true
      },
    )
    assert_true(
      try {
        s.set_row_height_length(1, v)
        false
      } catch {
        _ => true
      },
    )
    assert_eq(w.to_ods(), before)
  }
}
