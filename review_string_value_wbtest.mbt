///|
test "explicit string value is authoritative over valid differing display" {
  for
    pair in [
      ("stored", "shown"),
      ("", "shown"),
      ("a&#13;b", "a<x:line-break/>b"),
    ] {
    let r = import_content(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type='string' o:string-value='\{pair.0}'><x:p>\{pair.1}</x:p></t:table-cell></t:table-row>",
      ),
    )
    let expected = if pair.0 == "a&#13;b" { "a\rb" } else { pair.0 }
    assert_eq(
      r.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text(expected),
    )
    assert_true(
      r
      .diagnostics()
      .iter()
      .any(d => {
        d.code == "STRING_DISPLAY_TEXT_DROPPED" && d.row == 0 && d.col == 0
      }),
    )
  }
}

///|
test "string display diagnostics distinguish absence equality and explicit empty display" {
  for
    (attr, display, expected, loss) in [
      ("o:string-value='same'", "<x:p>same</x:p>", "same", false),
      ("o:string-value='stored'", "", "stored", false),
      ("o:string-value='stored'", "<x:p/>", "stored", true),
      ("", "<x:p>shown</x:p>", "shown", false),
      ("o:string-value='  a  '", "<x:p>a</x:p>", "  a  ", true),
    ] {
    let r = import_content(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type='string' \{attr}>\{display}</t:table-cell></t:table-row>",
      ),
    )
    assert_eq(
      r.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text(expected),
    )
    assert_eq(
      r.diagnostics().iter().any(d => d.code == "STRING_DISPLAY_TEXT_DROPPED"),
      loss,
    )
  }
}

///|
test "authoritative string value does not bypass display validation" {
  let bad = "<t:table-row><t:table-cell o:value-type='string' o:string-value='safe'><x:p><x:a>unsafe</x:a></x:p></t:table-cell></t:table-row>"
  assert_true(
    try {
      import_content(reader_xml_fixture(bad)) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "repeated distinct string displays retain bounded counted diagnostics" {
  let r = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated='100'><t:table-cell t:number-columns-repeated='100' o:value-type='string' o:string-value='stored'><x:p>shown</x:p></t:table-cell></t:table-row>",
    ),
  )
  let exact = r
    .diagnostics()
    .iter()
    .filter(d => d.code == "STRING_DISPLAY_TEXT_DROPPED")
    .count()
  let summaries = r
    .diagnostics()
    .iter()
    .filter(d => d.code == "STRING_DISPLAY_TEXT_DROPPED_SUMMARY")
    .collect()
  assert_eq(exact, 32)
  assert_eq(summaries.length(), 1)
  assert_true(summaries[0].message.contains("9968 additional occurrences"))
  assert_eq(
    r.workbook().sheet(0).unwrap().get(99, 99).unwrap().value(),
    Text("stored"),
  )
}
