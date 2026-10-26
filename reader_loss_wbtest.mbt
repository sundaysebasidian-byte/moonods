///|
fn loss_case(cell : String) -> ImportResult raise OdsError {
  import_content(reader_xml_fixture("<t:table-row>\{cell}</t:table-row>"))
}

///|
test "precision loss is reported at the exact cell instead of silent rounding" {
  for
    raw in [
      "9007199254740993", "1.0000000000000001", "12345678901234567890.123456789",
    ] {
    let imported = loss_case(
      "<t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/>",
    )
    assert_true(
      imported
      .diagnostics()
      .iter()
      .any(d => {
        d.code == "NUMBER_PRECISION_CHANGED" &&
        d.sheet == "Input" &&
        d.row == 0 &&
        d.col == 0 &&
        d.message.contains(raw)
      }),
    )
    let s = imported.workbook().sheet(0).unwrap()
    let reread = read_ods(
        imported.workbook().to_ods(),
        allow_formatting_loss=true,
      )
      .workbook()
      .sheet(0)
      .unwrap()
    assert_eq(reread.get(0, 0).unwrap().value(), s.get(0, 0).unwrap().value())
  }
}

///|
test "equivalent decimal spellings do not create false precision loss warnings" {
  for
    raw in [
      "1.00", "+1E+2", "000.5000", "10e-1", "0.1", "9007199254740992", "-0.00",
    ] {
    let imported = loss_case(
      "<t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/>",
    )
    assert_false(
      imported
      .diagnostics()
      .iter()
      .any(d => d.code == "NUMBER_PRECISION_CHANGED"),
    )
  }
}

///|
test "nonzero underflow rejects rather than silently turning into zero" {
  for raw in ["1e-9999", "-1e-9999", "1e-324", "-1e-324"] {
    let error = try {
      loss_case("<t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/>")
      |> ignore
      ""
    } catch {
      Invalid(msg) => msg
    }
    assert_true(error.contains("underflows to zero"))
    assert_true(error.contains("row 0 col 0"))
  }
  assert_true(read_finite_double("5e-324") > 0.0)
  assert_eq(read_finite_double("0e-9999"), 0.0)
}

///|
test "numeric formula cache precision has its own diagnostic" {
  let imported = loss_case(
    "<t:table-cell xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" t:formula=\"of:=9007199254740993\" o:value-type=\"float\" o:value=\"9007199254740993\"/>",
  )
  assert_true(
    imported.diagnostics().iter().any(d => d.code == "NUMBER_PRECISION_CHANGED"),
  )
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => d.code == "FORMULA_CACHE_NOT_RECALCULATED"),
  )
  assert_eq(
    imported.workbook().sheet(0).unwrap().get(0, 0).unwrap().expression(),
    Some("of:=9007199254740993"),
  )
}

///|
test "known omitted package parts and automatic styles are individually disclosed" {
  let imported = read_ods(
    reader_fixture("libreoffice-dev-types"),
    allow_formatting_loss=true,
  )
  for
    part in [
      "styles.xml", "settings.xml", "meta.xml", "manifest.rdf", "Thumbnails/thumbnail.png",
    ] {
    assert_true(
      imported
      .diagnostics()
      .iter()
      .any(d => d.code == "PACKAGE_PART_DROPPED" && d.message.contains(part)),
    )
  }
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "DOCUMENT_FORMATTING_DROPPED" &&
      d.message.contains("automatic-styles")
    }),
  )
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => d.code == "FORMATTING_DROPPED" && d.row == 0 && d.col == 2),
  )
}

///|
test "nonempty named ranges and formulas without caches refuse with useful feature identity" {
  let xml = reader_xml_fixture(
    "<t:named-expressions><t:named-range t:name=\"MyRange\" t:cell-range-address=\"Input.A1\"/></t:named-expressions>",
  )
  let error = try {
    import_content(xml) |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("named-expressions"))
  let spreadsheet_scope = reader_xml_fixture("").replace(
    old="</o:spreadsheet>",
    new="<t:named-expressions><t:named-range t:name=\"MyRange\" t:cell-range-address=\"Input.A1\"/></t:named-expressions></o:spreadsheet>",
  )
  let spreadsheet_error = try {
    import_content(spreadsheet_scope) |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(spreadsheet_error.contains("unsupported spreadsheet feature"))
  assert_true(spreadsheet_error.contains("named-expressions"))
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" t:formula=\"of:=1+2\"/></t:table-row>",
      ),
    ),
  )
}

///|
test "styles cannot smuggle unsupported semantic children and covered values are never dropped" {
  for
    cell in [
      "<t:table-cell t:style-name=\"Custom\" o:value-type=\"string\"><x:p><x:a>link</x:a></x:p></t:table-cell>",
      "<t:table-cell o:value-type=\"float\" o:value=\"1\"><o:annotation><x:p>note</x:p></o:annotation></t:table-cell>",
      "<t:table-cell t:number-columns-spanned=\"2\"/><t:covered-table-cell o:value-type=\"float\" o:value=\"2\"/>",
    ] {
    assert_true(
      reader_xml_rejects(
        reader_xml_fixture("<t:table-row>\{cell}</t:table-row>"),
      ),
    )
  }
}

///|
test "date empty blank and significant whitespace remain distinct in edited output" {
  let imported = loss_case(
    "<t:table-cell o:value-type=\"date\" o:date-value=\"2000-02-29\"/><t:table-cell o:value-type=\"string\"/><t:table-cell/><t:table-cell o:value-type=\"string\"><x:p> </x:p></t:table-cell>",
  )
  let w = read_ods(imported.workbook().to_ods(), allow_formatting_loss=true).workbook()
  let s = w.sheet(0).unwrap()
  assert_eq(s.get(0, 0).unwrap().value(), Date(2000, 2, 29))
  assert_eq(s.get(0, 1).unwrap().value(), Text(""))
  assert_eq(s.get(0, 2).unwrap().value(), Empty)
  assert_eq(s.get(0, 3).unwrap().value(), Text(" "))
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"date\" o:date-value=\"2100-02-29\"/></t:table-row>",
      ),
    ),
  )
}

///|
test "negative zero retains sign through typed reading editing and writing" {
  let imported = loss_case(
    "<t:table-cell o:value-type=\"float\" o:value=\"-0.00\"/>",
  )
  let before = imported.workbook().sheet(0).unwrap().get(0, 0).unwrap().value()
  match before {
    Number(n) => assert_true(1.0 / n < 0.0)
    _ => fail("not numeric")
  }
  let out = imported.workbook().to_ods()
  let after = read_ods(out, allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
    .get(0, 0)
    .unwrap()
    .value()
  match after {
    Number(n) => assert_true(1.0 / n < 0.0)
    _ => fail("not numeric")
  }
  assert_true(imported.workbook().content_xml().contains("office:value=\"-0\""))
}

///|
test "precision diagnostics and numeric parsing have independent resource caps" {
  let b = StringBuilder()
  for _ in 0..<1025 {
    b.write_char('1')
  }
  let oversized = b.to_string()
  let error = try {
    read_finite_double(oversized) |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("1024"))
  let b = StringBuilder()
  for _ in 0..<200 {
    b.write_char('1')
  }
  b.write_string("e-200")
  let raw = b.to_string()
  let imported = loss_case(
    "<t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/>",
  )
  let notices = imported
    .diagnostics()
    .filter(d => d.code == "NUMBER_PRECISION_CHANGED")
  assert_eq(notices.length(), 1)
  assert_true(notices[0].message.length() < 256)
}

///|
test "large pure empty tail is bounded and disclosed without shifting content" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row><t:table-cell o:value-type=\"float\" o:value=\"12345\"/></t:table-row>" +
      "<t:table-row t:number-rows-repeated=\"1048574\"><t:table-cell t:number-columns-repeated=\"2\"/></t:table-row><t:table-row><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Number(12345.0),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions().0, 1)
  assert_true(
    result.diagnostics().iter().any(d => d.code == "EMPTY_TAIL_ROWS_DROPPED"),
  )
  read_ods(result.workbook().to_ods(), allow_formatting_loss=true) |> ignore
}

///|
test "empty tail policy never discards content or expands huge counts" {
  for
    suffix in [
      "<t:table-row t:number-rows-repeated=\"1048577\"><t:table-cell/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"999999999999999999999999999999\"><t:table-cell/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"0\"><t:table-cell/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048576\"><t:table-cell o:value-type=\"float\" o:value=\"1\"/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048576\"><t:table-cell t:formula=\"of:=1\"/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048576\"><t:table-cell t:number-rows-spanned=\"2\"/></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048576\"><t:table-cell><o:annotation/></t:table-cell></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048575\"><t:table-cell/></t:table-row><t:table-row><t:table-cell o:value-type=\"float\" o:value=\"1\"/></t:table-row>",
    ] {
    let rejected = try {
      import_content(reader_xml_fixture(suffix)) |> ignore
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}
