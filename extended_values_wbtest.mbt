///|
test "extended value constructors keep financial units and temporal lexical data" {
  let values = [
    Percentage(0.25),
    Currency(12.5, "USD"),
    Duration("-P2DT1H30M0.123S"),
    DateTime("2026-10-26T01:30:00.123+08:00"),
    DateTime("2026-10-26T01:30:00Z"),
    DateTime("2026-10-26T01:30:00"),
  ]
  let book = Workbook::new()
  let sheet = book.add_sheet("Extended")
  for col, value in values {
    sheet.set(0, col, Cell::new(value))
  }
  let bytes = book.to_ods()
  let error = try {
    read_ods(bytes, allow_formatting_loss=true) |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error != "")
  let again = read_ods(
      bytes,
      allow_formatting_loss=true,
      allow_extended_types=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  for col, value in values {
    assert_eq(again.get(0, col).unwrap().value(), value)
  }
}

///|
test "extended parsing preserves kind amount code and decimal loss notice" {
  let xml = reader_xml_fixture(
    "<t:table-row><t:table-cell o:value-type=\"percentage\" o:value=\"9007199254740993\"/><t:table-cell o:value-type=\"percentage\" o:value=\"-0\"/><t:table-cell o:value-type=\"time\" o:time-value=\"PT25H\"/><t:table-cell o:value-type=\"date\" o:date-value=\"2024-02-29T23:59:59-14:00\"/></t:table-row>",
  )
  let result = import_content(xml, allow_extended_types=true)
  assert_true(
    result
    .diagnostics()
    .iter()
    .any(d => d.code == "NUMBER_PRECISION_CHANGED" && d.col == 0),
  )
  let sheet = result.workbook().sheet(0).unwrap()
  assert_eq(sheet.get(0, 0).unwrap().value(), Percentage(9007199254740992.0))
  match sheet.get(0, 1).unwrap().value() {
    Percentage(n) => assert_true(1.0 / n < 0.0)
    _ => fail("percentage coerced")
  }
  assert_eq(sheet.get(0, 2).unwrap().value(), Duration("PT25H"))
  assert_eq(
    sheet.get(0, 3).unwrap().value(),
    DateTime("2024-02-29T23:59:59-14:00"),
  )
  read_ods(
    result.workbook().to_ods(),
    allow_formatting_loss=true,
    allow_extended_types=true,
  )
  |> ignore
}

///|
test "extended financial and temporal malformed values refuse without coercion" {
  for
    value in [
      Currency(1.0, ""),
      Currency(1.0, "usd"),
      Currency(1.0, "USDD"),
      Currency(1.0, "U\"D"),
      Currency(1.0 / 0.0, "USD"),
      Percentage(0.0 / 0.0),
      Duration("P1Y"),
      Duration("P1M"),
      Duration("PT"),
      Duration("P1DT"),
      Duration("PT1.2H"),
      Duration("PT1S2S"),
      Duration("PT9999999999S"),
      Duration("PT1.1234567890S"),
      DateTime("2025-02-29T01:00:00"),
      DateTime("2026-10-26T24:00:00"),
      DateTime("2026-10-26T01:00:60Z"),
      DateTime("2026-10-26T01:00:00+14:01"),
      DateTime("2026-10-26T01:00:00+8:00"),
      DateTime("2026-10-26T01:00:00."),
      DateTime("2026-10-26T01:00:00Zjunk"),
    ] {
    assert_true(
      try {
        Cell::new(value) |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  for
    attrs in [
      "o:value-type=\"currency\" o:value=\"9007199254740993\" o:currency=\"USD\"",
      "o:value-type=\"currency\" o:value=\"1\"", "o:value-type=\"time\" o:time-value=\"PT1H\" o:value=\"1\"",
      "o:value-type=\"date\" o:date-value=\"2026-10-26T01:00:00Z\" o:boolean-value=\"true\"",
    ] {
    let error = try {
      import_content(
        reader_xml_fixture(
          "<t:table-row><t:table-cell \{attrs}/></t:table-row>",
        ),
        allow_extended_types=true,
      )
      |> ignore
      ""
    } catch {
      Invalid(msg) => msg
    }
    assert_true(error.contains("row 0 col 0"))
  }
}

///|
test "extended records retain kinds and CSV requires explicit tagged-text policy" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Records")
  sheet.set_row(0, 0, [
    Cell::new(Text("Ratio")),
    Cell::new(Text("Money")),
    Cell::new(Text("Elapsed")),
    Cell::new(Text("Instant")),
  ])
  let values = [
    Percentage(0.25),
    Currency(12.5, "USD"),
    Duration("PT1H30M"),
    DateTime("2026-10-26T01:30:00+08:00"),
  ]
  for c, v in values {
    sheet.set(1, c, Cell::new(v))
  }
  assert_eq(sheet.records()[0].values["Money"], Currency(12.5, "USD"))
  assert_true(
    try {
      sheet.to_csv() |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
  let csv = sheet.to_csv(extended_types_as_text=true)
  assert_true(csv.contains("currency:USD:12.5"))
  assert_true(csv.contains("percentage:0.25"))
  assert_true(csv.contains("duration:PT1H30M"))
  assert_true(csv.contains("datetime:2026-10-26T01:30:00+08:00"))
}

///|
test "typed format definition budget accepts boundary and refuses excess without mutation" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Definitions")
  for i in 0..<512 {
    let code = StringBuilder()
    code.write_char((65 + i / 676).unsafe_to_char())
    code.write_char((65 + i / 26 % 26).unsafe_to_char())
    code.write_char((65 + i % 26).unsafe_to_char())
    sheet.set(i, 0, Cell::new(Currency(1.0, code.to_string())))
  }
  let bytes = book.to_ods()
  assert_true(bytes.length() > 0)
  sheet.set(512, 0, Cell::new(Currency(1.0, "ZZZ")))
  let before = book.content_xml()
  let error = try {
    book.to_ods() |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("typed number-format definition budget exceeded"))
  assert_eq(book.content_xml(), before)
}
