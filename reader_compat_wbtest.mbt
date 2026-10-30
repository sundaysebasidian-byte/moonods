///|
test "compat nested spans preserve whitespace and typed values with cell notices" {
  let result = loss_case(
    "<t:table-cell o:value-type=\"string\"><x:p>A<x:span x:style-name=\"Bold\">中<x:span>文<x:s x:c=\"2\"/><x:tab/><x:line-break/>尾</x:span></x:span>Z</x:p></t:table-cell>",
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text("A中文  \t\n尾Z"),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "RICH_TEXT_FORMATTING_DROPPED" &&
      d.sheet == "Input" &&
      d.row == 0 &&
      d.col == 0
    }),
  )
}

///|
test "compat tail uses prefix row budget" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated=\"1000\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/></t:table-row><t:table-row t:number-rows-repeated=\"25\"><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions(), (1000, 1))
  assert_eq(
    result.workbook().sheet(0).unwrap().get(999, 0).unwrap().value(),
    Number(7.0),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "EMPTY_TAIL_ROWS_DROPPED" &&
      d.row == 1000 &&
      d.message.contains("25")
    }),
  )
}

///|
test "compat completed merge does not prevent pure tail omission" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row><t:table-cell t:number-columns-spanned=\"2\"/><t:covered-table-cell/></t:table-row><t:table-row t:number-rows-repeated=\"1048575\"><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions(), (1, 2))
  assert_eq(result.workbook().sheet(0).unwrap().merge_span(0, 0), Some((1, 2)))
}

///|
test "compat numeric and formula rich display retains values and formula cache" {
  let result = loss_case(
    "<t:table-cell xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" t:formula=\"of:=1+2\" o:value-type=\"float\" o:value=\"3\"><x:p x:style-name=\"P\"><x:span x:style-name=\"N\">USD 3.00</x:span></x:p></t:table-cell>",
  )
  let cell = result.workbook().sheet(0).unwrap().get(0, 0).unwrap()
  assert_eq(cell.value(), Number(3.0))
  assert_eq(cell.expression(), Some("of:=1+2"))
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "RICH_TEXT_FORMATTING_DROPPED" && d.row == 0 && d.col == 0
    }),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => d.code == "FORMULA_CACHE_NOT_RECALCULATED"),
  )
  let after = read_ods(result.workbook().to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
    .get(0, 0)
    .unwrap()
  assert_eq(after.value(), cell.value())
  assert_eq(after.expression(), cell.expression())
}

///|
test "compat empty spans paragraphs and string attributes remain distinct" {
  let result = loss_case(
    "<t:table-cell o:value-type=\"string\"><x:p><x:span/></x:p><x:p><x:span>尾</x:span></x:p></t:table-cell>",
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text("\n尾"),
  )
  let result = loss_case(
    "<t:table-cell o:value-type=\"string\"><x:p><x:span/></x:p></t:table-cell>",
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text(""),
  )
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"string\" o:string-value=\"different\"><x:p><x:span>text</x:span></x:p></t:table-cell></t:table-row>",
      ),
    ),
  )
}

///|
test "compat spans do not admit links scripts unknown nodes or attributes" {
  for
    inner in [
      "<x:span><x:a>link</x:a></x:span>", "<x:span><o:scripts/></x:span>", "<x:span x:unknown=\"1\">text</x:span>",
      "<x:span><x:unknown/></x:span>", "<x:span><x:s x:c=\"-1\"/></x:span>", "<x:span><x:tab>nonempty</x:tab></x:span>",
    ] {
    for kind in ["string", "float"] {
      let typed = if kind == "float" { " o:value=\"1\"" } else { "" }
      let error = try {
        loss_case(
          "<t:table-cell o:value-type=\"\{kind}\"\{typed}><x:p>\{inner}</x:p></t:table-cell>",
        )
        |> ignore
        ""
      } catch {
        Invalid(msg) => msg
      }
      assert_true(error.contains("sheet 'Input' row 0 col 0"))
    }
  }
}

///|
test "compat rich text preserves depth and expanded cell limits" {
  let max = loss_case(
    "<t:table-cell o:value-type=\"string\"><x:p><x:span><x:s x:c=\"32767\"/></x:span></x:p></t:table-cell>",
  )
  match max.workbook().sheet(0).unwrap().get(0, 0).unwrap().value() {
    Text(t) => assert_eq(t.length(), 32767)
    _ => fail("expected text")
  }
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"string\"><x:p><x:span><x:s x:c=\"32767\"/></x:span><x:span>x</x:span></x:p></t:table-cell></t:table-row>",
      ),
    ),
  )
  let b = StringBuilder()
  for _ in 0..<40 {
    b.write_string("<x:span>")
  }
  for _ in 0..<40 {
    b.write_string("</x:span>")
  }
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"string\"><x:p>\{b.to_string()}</x:p></t:table-cell></t:table-row>",
      ),
    ),
  )
}

///|
test "compat in budget tail stays at original positions" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated=\"1000\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/></t:table-row><t:table-row t:number-rows-repeated=\"24\"><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions(), (1024, 1))
  assert_eq(
    result.workbook().sheet(0).unwrap().get(999, 0).unwrap().value(),
    Number(7.0),
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(1023, 0).unwrap().value(),
    Empty,
  )
  assert_false(
    result.diagnostics().iter().any(d => d.code == "EMPTY_TAIL_ROWS_DROPPED"),
  )
}

///|
test "compat suffix respects grid budget even if row count fits" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated=\"512\"><t:table-cell t:number-columns-repeated=\"128\" o:value-type=\"float\" o:value=\"7\"/></t:table-row><t:table-row><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions(), (512, 128))
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => d.code == "EMPTY_TAIL_ROWS_DROPPED" && d.row == 512),
  )
  let wide = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated=\"1000\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/></t:table-row><t:table-row><t:table-cell t:number-columns-repeated=\"128\"/></t:table-row>",
    ),
  )
  assert_eq(wide.workbook().sheet(0).unwrap().dimensions(), (1000, 1))
}

///|
test "compat suffix respects remaining workbook grid budget" {
  let b = StringBuilder()
  for i in 0..<4 {
    b.write_string(
      "<t:table t:name=\"S\{i}\"><t:table-row t:number-rows-repeated=\"500\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/><t:table-cell t:number-columns-repeated=\"127\"/></t:table-row></t:table>",
    )
  }
  b.write_string(
    "<t:table t:name=\"Last\"><t:table-row t:number-rows-repeated=\"48\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/><t:table-cell t:number-columns-repeated=\"127\"/></t:table-row><t:table-row/></t:table>",
  )
  let result = import_content(review_book_xml(b.to_string())) catch {
    Invalid(msg) => fail(msg)
  }
  assert_eq(result.workbook().sheet(4).unwrap().dimensions(), (48, 128))
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => d.code == "EMPTY_TAIL_ROWS_DROPPED" && d.sheet == "Last"),
  )
}

///|
test "compat vertical merge wholly retained survives tail omission and roundtrip" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row><t:table-cell t:number-rows-spanned=\"2\" o:value-type=\"string\"><x:p><x:span>合并</x:span></x:p></t:table-cell></t:table-row><t:table-row><t:covered-table-cell/></t:table-row><t:table-row t:number-rows-repeated=\"1048574\"/>",
    ),
  )
  let sheet = result.workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions(), (2, 1))
  assert_eq(sheet.merge_span(0, 0), Some((2, 1)))
  let again = read_ods(result.workbook().to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(again.merge_span(0, 0), Some((2, 1)))
  assert_true(again.is_covered(1, 0))
}

///|
test "compat tail crossing merge and nonempty suffixes still refuse" {
  for
    suffix in [
      "<t:table-row t:number-rows-repeated=\"1048575\"/>", "<t:table-row t:number-rows-repeated=\"1048575\"><t:table-cell o:value-type=\"string\"><x:p/></t:table-cell></t:table-row>",
      "<t:table-row t:number-rows-repeated=\"1048575\"><t:table-cell><o:annotation/></t:table-cell></t:table-row>",
    ] {
    assert_true(
      reader_xml_rejects(
        reader_xml_fixture(
          "<t:table-row><t:table-cell t:number-rows-spanned=\"2\"/></t:table-row>" +
          suffix,
        ),
      ),
    )
  }
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row t:number-rows-repeated=\"1000\"><t:table-cell o:value-type=\"float\" o:value=\"7\"/></t:table-row><t:table-row t:number-rows-repeated=\"25\"/><t:table-row><t:table-cell o:value-type=\"float\" o:value=\"8\"/></t:table-row>",
      ),
    ),
  )
}

///|
test "compat completely blank huge sheet remains bounded" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated=\"1048576\"><t:table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().dimensions(), (1, 1))
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => d.code == "EMPTY_TAIL_ROWS_DROPPED" && d.row == 0),
  )
  read_ods(result.workbook().to_ods(), allow_formatting_loss=true) |> ignore
}

///|
test "compat simple row column header containers keep positions and disclose metadata" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-header-columns><t:table-column/></t:table-header-columns><t:table-columns><t:table-column/></t:table-columns><t:table-header-rows><t:table-row><t:table-cell o:value-type=\"string\"><x:p>Header</x:p></t:table-cell></t:table-row></t:table-header-rows><t:table-rows><t:table-row><t:table-cell o:value-type=\"float\" o:value=\"7\"/></t:table-row></t:table-rows>",
    ),
  )
  let sheet = result.workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions(), (2, 2))
  assert_eq(sheet.get(0, 0).unwrap().value(), Text("Header"))
  assert_eq(sheet.get(1, 0).unwrap().value(), Number(7.0))
  assert_eq(
    result
    .diagnostics()
    .filter(d => d.code == "TABLE_HEADER_METADATA_DROPPED")
    .length(),
    2,
  )
  let again = read_ods(result.workbook().to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(again.get(1, 0).unwrap().value(), Number(7.0))
}

///|
test "compat container malicious neighbors and placement continue to refuse" {
  for
    content in [
      "<t:table-header-rows t:display=\"false\"><t:table-row/></t:table-header-rows>",
      "<t:table-rows><o:scripts/></t:table-rows>", "<t:table-header-rows/>", "<t:table-header-columns><t:table-row/></t:table-header-columns>",
      "<t:table-row/><t:table-columns><t:table-column/></t:table-columns>", "<t:table-row-group><t:table-row/></t:table-row-group>",
    ] {
    assert_true(reader_xml_rejects(reader_xml_fixture(content)))
  }
}

///|
test "compat formatting notices classify width row and cell losses with coordinates" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-column t:style-name=\"W40\"/><t:table-row t:style-name=\"R20\"><t:table-cell t:style-name=\"Money\" o:value-type=\"float\" o:value=\"2\"/></t:table-row>",
    ),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "FORMATTING_DROPPED" &&
      d.row == -1 &&
      d.col == 0 &&
      d.message.contains("column style/width") &&
      d.message.contains("W40")
    }),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.row == 0 && d.col == -1 && d.message.contains("row style/height")
    }),
  )
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.row == 0 &&
      d.col == 0 &&
      d.message.contains("cell style/number-format") &&
      d.message.contains("Money")
    }),
  )
}

///|
test "compat unsupported financial and temporal units never silently coerce" {
  for
    cell in [
      "<t:table-cell o:value-type=\"percentage\" o:value=\"0.25\"/>", "<t:table-cell o:value-type=\"currency\" o:value=\"12.5\" o:currency=\"USD\"/>",
      "<t:table-cell o:value-type=\"time\" o:time-value=\"PT1H30M\"/>", "<t:table-cell o:value-type=\"date\" o:date-value=\"2026-10-26T01:30:00+08:00\"/>",
    ] {
    let error = try {
      loss_case(cell) |> ignore
      ""
    } catch {
      Invalid(msg) => msg
    }
    assert_true(error.contains("sheet 'Input' row 0 col 0"))
    assert_true(error != "")
  }
}

///|
test "compat LibreOffice styled covered cells keep coverage and report loss" {
  let prefix = "<t:table-row><t:table-cell t:number-rows-spanned=\"2\" t:number-columns-spanned=\"2\"/><t:covered-table-cell/></t:table-row>"
  let result = import_content(
    reader_xml_fixture(
      prefix +
      "<t:table-row><t:covered-table-cell t:style-name=\"Default\"/><t:covered-table-cell/></t:table-row>",
    ),
  )
  assert_eq(result.workbook().sheet(0).unwrap().merge_span(0, 0), Some((2, 2)))
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "FORMATTING_DROPPED" &&
      d.row == 1 &&
      d.col == 0 &&
      d.message.contains("Default")
    }),
  )
  for
    covered in [
      "<t:covered-table-cell t:style-name=\"Default\" o:value-type=\"float\" o:value=\"1\"/>",
      "<t:covered-table-cell t:style-name=\"Default\" t:formula=\"of:=1\"/>", "<t:covered-table-cell t:style-name=\"Default\"><x:p>hidden</x:p></t:covered-table-cell>",
    ] {
    assert_true(
      reader_xml_rejects(
        reader_xml_fixture(
          prefix +
          "<t:table-row>" +
          covered +
          "<t:covered-table-cell/></t:table-row>",
        ),
      ),
    )
  }
}
