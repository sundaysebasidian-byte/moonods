///|
fn xsd_case(attrs : String) -> ImportResult raise OdsError {
  import_content(
    reader_xml_fixture("<t:table-row><t:table-cell \{attrs}/></t:table-row>"),
    allow_extended_types=true,
  )
}

///|
test "XSD typed whitespace collapse preserves number precision checks" {
  for raw in [" +1.25 ", "&#x9;+1.25&#xA;", "&#xD;1.25&#x9;"] {
    let r = xsd_case("o:value-type='float' o:value='\{raw}'")
    assert_eq(
      r.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      Number(1.25),
    )
    assert_false(
      r.diagnostics().iter().any(d => d.code == "NUMBER_PRECISION_CHANGED"),
    )
  }
  let r = xsd_case("o:value-type='float' o:value=' 9007199254740993 '")
  assert_true(
    r.diagnostics().iter().any(d => d.code == "NUMBER_PRECISION_CHANGED"),
  )
  for
    raw in [
      "1 2", "+ 1", "1&#x9;2", " 1.25 ", "1_2", "NaN", " INF ", " 1e-9999 ",
    ] {
    assert_true(
      try {
        xsd_case("o:value-type='float' o:value='\{raw}'") |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "XSD positive integer accepts plus only in count position" {
  for v in ["+2", " 2 ", "&#x9;+2&#xA;"] {
    let r = import_content(
      reader_xml_fixture(
        "<t:table-row t:number-rows-repeated='\{v}'><t:table-cell t:number-columns-repeated='\{v}' o:value-type='float' o:value='7'/></t:table-row>",
      ),
    )
    let s = r.workbook().sheet(0).unwrap()
    assert_eq(s.get(1, 1).unwrap().value(), Number(7.0))
  }
  for v in ["0", "-2", "+ 2", "2.0", "2 2", " 2 ", "999999999999999999999"] {
    assert_true(
      try {
        read_xsd_positive(v, 128) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(physical_length("+1mm"), None)
  assert_true(
    try {
      xsd_case("o:value-type='date' o:date-value='+001-01-01'") |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "ODF token boolean accepts collapsed true false not XSD numeric aliases" {
  for (raw, value) in [(" true ", true), ("&#x9;false&#xA;", false)] {
    assert_eq(
      xsd_case("o:value-type=' boolean ' o:boolean-value='\{raw}'")
      .workbook()
      .sheet(0)
      .unwrap()
      .get(0, 0)
      .unwrap()
      .value(),
      Boolean(value),
    )
  }
  for raw in ["1", "0", "TRUE", "t rue", " true "] {
    assert_true(
      try {
        xsd_case("o:value-type='boolean' o:boolean-value='\{raw}'") |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "typed date duration percentage currency collapse while string preserves" {
  for
    (attrs, value) in [
      ("o:value-type='date' o:date-value=' 2024-02-29 '", Date(2024, 2, 29)),
      (
        "o:value-type='date' o:date-value='&#x9;2024-02-29T12:00:00Z&#xA;'",
        DateTime("2024-02-29T12:00:00Z"),
      ),
      ("o:value-type='time' o:time-value=' PT1H '", Duration("PT1H")),
      ("o:value-type='percentage' o:value=' +0.5 '", Percentage(0.5)),
      (
        "o:value-type='currency' o:currency='USD' o:value=' 1.25 '",
        Currency(1.25, "USD"),
      ),
      ("o:value-type=' string ' o:string-value='  a  '", Text("  a  ")),
    ] {
    assert_eq(
      xsd_case(attrs).workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      value,
    )
  }
}

///|
test "date parts stay strict and text s nonnegative zero is distinct from positive counts" {
  for
    raw in [
      "2026-+10-30", "2026-10-+3", "+026-10-30", "2026- 1-30", "2026-10-3 ", "2026-10-00",
    ] {
    assert_true(
      try {
        xsd_case("o:value-type='date' o:date-value='\{raw}'") |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  for raw in ["0", "+0", "-0", " -000 ", "&#x9;+0&#xA;"] {
    assert_eq(paragraph_case("<x:p>a<x:s x:c='\{raw}'/>b</x:p>"), "ab")
  }
  for raw in ["-1", "+ 0", "0.0", "999999999999999999999"] {
    assert_true(
      try {
        paragraph_case("<x:p>a<x:s x:c='\{raw}'/>b</x:p>") |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}
