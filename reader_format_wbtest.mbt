///|
fn format_case(styles : String, table : String) -> ImportResult raise OdsError {
  let xml = "<office:document-styles\{namespaces} office:version=\"1.3\"><office:styles>\{styles}</office:styles></office:document-styles>"
  import_content(reader_xml_fixture(table), preserve_basic_formatting=true, styles=[
    xml,
  ])
}

///|
test "basic formatting reads actual writer presets and exact widths twice" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Styles")
  let presets = [Plain, Header, Highlight, Decimal2, DateISO]
  for c, style in presets {
    sheet.set(0, c, Cell::new(Text("style")).styled(style))
  }
  sheet.set_column_width(0, 1)
  sheet.set_column_width(1, 40)
  sheet.set_column_width(2, 500)
  let bytes = book.to_ods()
  let legacy = read_ods(bytes, allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(legacy.get(0, 1).unwrap().style(), Plain)
  assert_eq(legacy.column_width(1), None)
  let imported = read_ods(
    bytes,
    allow_formatting_loss=true,
    preserve_basic_formatting=true,
  )
  let result = imported.workbook().sheet(0).unwrap()
  for c, style in presets {
    assert_eq(result.get(0, c).unwrap().style(), style)
  }
  for (c, mm) in [(0, 1), (1, 40), (2, 500)] {
    assert_eq(result.column_width(c), Some(mm))
  }
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "BASIC_FORMATTING_SUBSET" && d.message.contains("5 normalized")
    }),
  )
  let again = read_ods(
      imported.workbook().to_ods(),
      allow_formatting_loss=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  for c, style in presets {
    assert_eq(again.get(0, c).unwrap().style(), style)
  }
  assert_eq(again.column_width(1), Some(40))
}

///|
test "basic formatting resolves defaults parents and renamed definitions not names" {
  let defs = "<style:default-style style:family=\"table-cell\"><style:table-cell-properties fo:wrap-option=\"wrap\"/></style:default-style><style:style style:name=\"Parent\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#FFF2CC\"/></style:style><style:style style:name=\"Header\" style:family=\"table-cell\" style:parent-style-name=\"Parent\"/>"
  let result = format_case(
    defs, "<t:table-row><t:table-cell t:style-name=\"Header\" o:value-type=\"string\"><x:p>hello</x:p></t:table-cell></t:table-row>",
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().style(),
    Highlight,
  )
  let renamed = styles_xml()
    .replace_all(old="N2", new="RenamedNumber")
    .replace_all(old="Decimal2", new="RenamedCell")
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row><t:table-cell t:style-name=\"RenamedCell\" o:value-type=\"float\" o:value=\"1.25\"/></t:table-row>",
    ),
    preserve_basic_formatting=true,
    styles=[renamed],
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().style(),
    Decimal2,
  )
}

///|
test "basic default cell style precedence is explicit then row then column then family" {
  let table = "<t:table-column t:default-cell-style-name=\"Header\" t:number-columns-repeated=\"2\"/><t:table-row t:default-cell-style-name=\"Highlight\"><t:table-cell o:value-type=\"float\" o:value=\"1\"/><t:table-cell t:style-name=\"Decimal2\" o:value-type=\"float\" o:value=\"2\"/></t:table-row><t:table-row><t:table-cell o:value-type=\"float\" o:value=\"3\"/></t:table-row>"
  let result = import_content(
      reader_xml_fixture(table),
      preserve_basic_formatting=true,
      styles=[styles_xml()],
    )
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(result.get(0, 0).unwrap().style(), Highlight)
  assert_eq(result.get(0, 1).unwrap().style(), Decimal2)
  assert_eq(result.get(1, 0).unwrap().style(), Header)
}

///|
test "basic unknown cyclic missing and conflicting defaults do not guess" {
  for
    definitions in [
      "<style:style style:name=\"Header\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#000000\"/></style:style>",
      "<style:style style:name=\"Header\" style:family=\"table-cell\" style:parent-style-name=\"Missing\"/>",
      "<style:style style:name=\"Header\" style:family=\"table-cell\" style:parent-style-name=\"Loop\"/><style:style style:name=\"Loop\" style:family=\"table-cell\" style:parent-style-name=\"Header\"/>",
      "<style:default-style style:family=\"table-cell\"><style:text-properties fo:font-size=\"18pt\"/></style:default-style><style:style style:name=\"Header\" style:family=\"table-cell\"><style:table-cell-properties fo:wrap-option=\"wrap\"/></style:style>",
    ] {
    let result = format_case(
      definitions, "<t:table-row><t:table-cell t:style-name=\"Header\" o:value-type=\"float\" o:value=\"1\"/></t:table-row>",
    )
    assert_eq(
      result.workbook().sheet(0).unwrap().get(0, 0).unwrap().style(),
      Plain,
    )
    assert_true(
      result
      .diagnostics()
      .iter()
      .any(d => d.code == "FORMATTING_DROPPED" && d.row == 0 && d.col == 0),
    )
  }
  let duplicate = "<style:style style:name=\"A\" style:family=\"table-cell\"/><style:style style:name=\"A\" style:family=\"table-cell\"><style:text-properties fo:color=\"#FFFFFF\"/></style:style>"
  assert_true(
    try {
      format_case(duplicate, "<t:table-row/>") |> ignore
      false
    } catch {
      Invalid(msg) => msg.contains("ambiguous duplicate")
    },
  )
}

///|
test "basic width conversions are exact rational bounded and inherited" {
  for
    (raw, mm) in [
      ("1mm", 1),
      ("0.1cm", 1),
      ("4cm", 40),
      ("5in", 127),
      ("360pt", 127),
      ("30pc", 127),
      ("500.0mm", 500),
    ] {
    assert_eq(read_width_mm(raw), Some(mm))
  }
  for
    raw in [
      "0mm", "501mm", "1pt", "1in", "1px", "4%", "2*", "-1mm", "1.01cm", "999999999999999999mm",
      "1mmjunk", "+500.0mm",
    ] {
    assert_eq(read_width_mm(raw), None)
  }
  let defs = "<style:style style:name=\"Parent\" style:family=\"table-column\"><style:table-column-properties style:column-width=\"4cm\" style:use-optimal-column-width=\"false\"/></style:style><style:style style:name=\"Child\" style:family=\"table-column\" style:parent-style-name=\"Parent\"/>"
  let result = format_case(
      defs, "<t:table-column t:style-name=\"Child\" t:number-columns-repeated=\"2\"/><t:table-row/>",
    )
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(result.column_width(0), Some(40))
  assert_eq(result.column_width(1), Some(40))
  let default = "<style:default-style style:family=\"table-column\"><style:table-column-properties style:column-width=\"4cm\"/></style:default-style>"
  assert_eq(
    format_case(default, "<t:table-row><t:table-cell/></t:table-row>")
    .workbook()
    .sheet(0)
    .unwrap()
    .column_width(0),
    Some(40),
  )
}

///|
test "basic unknown width behavior and style script near-neighbors are never copied" {
  for
    properties in [
      "style:column-width=\"1px\"", "style:column-width=\"40mm\" style:use-optimal-column-width=\"true\"",
      "style:column-width=\"40mm\" style:rel-column-width=\"2*\"",
    ] {
    let result = format_case(
      "<style:style style:name=\"W40\" style:family=\"table-column\"><style:table-column-properties \{properties}/></style:style>",
      "<t:table-column t:style-name=\"W40\"/><t:table-row/>",
    )
    assert_eq(result.workbook().sheet(0).unwrap().column_width(0), None)
    assert_true(
      result
      .diagnostics()
      .iter()
      .any(d => {
        d.code == "FORMATTING_DROPPED" &&
        d.message.contains("column style/width")
      }),
    )
  }
  let result = format_case(
    "<style:style style:name=\"Header\" style:family=\"table-cell\"><office:scripts/></style:style>",
    "<t:table-row><t:table-cell t:style-name=\"Header\"/></t:table-row>",
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().style(),
    Plain,
  )
  assert_false(result.workbook().content_xml().contains("office:scripts"))
}

///|
test "typed number-format layering preserves model units and recognized base presets" {
  let book = Workbook::new()
  let sheet = book.add_sheet("TypedStyles")
  let values = [
    Currency(12.5, "USD"),
    Currency(12.5, "CNY"),
    Percentage(0.25),
    Duration("PT1H30M"),
    DateTime("2026-10-26T01:30:00+08:00"),
  ]
  for row, style in [Plain, Header, Highlight, Decimal2, DateISO] {
    for col, value in values {
      sheet.set(row, col, Cell::new(value).styled(style))
    }
  }
  let imported = read_ods(
    book.to_ods(),
    allow_formatting_loss=true,
    allow_extended_types=true,
    preserve_basic_formatting=true,
  )
  let again = imported.workbook().sheet(0).unwrap()
  for row, style in [Plain, Header, Highlight, Decimal2, DateISO] {
    for col, value in values {
      assert_eq(again.get(row, col).unwrap().value(), value)
      assert_eq(again.get(row, col).unwrap().style(), style)
    }
  }
}

///|
test "basic ordinary Office auto-break keeps an exact width but forced break does not" {
  for (mode, width) in [("auto", Some(127)), ("page", None)] {
    let definitions = "<style:style style:name=\"OfficeCol\" style:family=\"table-column\"><style:table-column-properties style:column-width=\"5in\" fo:break-before=\"\{mode}\"/></style:style>"
    let result = format_case(
      definitions, "<t:table-column t:style-name=\"OfficeCol\"/><t:table-row/>",
    )
    assert_eq(result.workbook().sheet(0).unwrap().column_width(0), width)
  }
}
