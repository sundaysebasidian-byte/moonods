///|
fn reader_rejects(name : String) -> Bool {
  try {
    read_ods(reader_fixture(name), allow_formatting_loss=true) |> ignore
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "typed reader distinguishes empty string and empty with namespace aliases" {
  let result = read_ods(
    reader_fixture("typed-prefix-alias"),
    allow_formatting_loss=true,
  )
  let s = result.workbook().sheet(0).unwrap()
  assert_eq(s.get(0, 0).unwrap().value(), Text(""))
  assert_eq(s.get(0, 1).unwrap().value(), Empty)
  assert_eq(s.get(0, 2).unwrap().value(), Number(1.25))
  assert_eq(s.get(0, 3).unwrap().value(), Boolean(false))
  assert_eq(s.get(0, 4).unwrap().value(), Date(2024, 2, 29))
  assert_eq(result.diagnostics()[0].code, "DATA_ONLY_IMPORT")
  assert_true(result.workbook().sheet(-1) is None)
  assert_true(result.workbook().sheet(1) is None)
}

///|
test "reader requires explicit data-only acceptance" {
  assert_true(
    try {
      read_ods(reader_fixture("typed-prefix-alias")) |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "all hostile controls fail through actual public reader" {
  for
    name in [
      "deep-xml", "dtd-entity", "duplicate-content", "forged-inflate-size", "formula-without-cache",
      "inflate-ratio", "invalid-date", "nonfinite-number", "repeat-overflow", "unknown-currency",
      "wrong-table-namespace",
    ] {
    assert_true(reader_rejects(name))
  }
}

///|
test "actual LibreOffice producer typed edit write reread preserves supported values" {
  let imported = read_ods(
    reader_fixture("libreoffice-dev-types"),
    allow_formatting_loss=true,
  )
  let w = imported.workbook()
  assert_eq(w.sheet_count(), 2)
  let s = w.sheet(0).unwrap()
  assert_eq(s.name(), "Types")
  assert_eq(s.get(0, 1).unwrap().value(), Boolean(true))
  assert_eq(s.get(0, 2).unwrap().value(), Date(2024, 2, 29))
  assert_eq(s.get(0, 3).unwrap().value(), Text(" leading \t中\n文 "))
  assert_eq(s.get(0, 4).unwrap().value(), Text(""))
  assert_eq(s.get(0, 5).unwrap().value(), Empty)
  for r in [1, 2] {
    for c in [0, 1] {
      assert_eq(s.get(r, c).unwrap().value(), Number(7.5))
    }
  }
  assert_eq(s.get(0, 6).unwrap().expression(), Some("of:=1+2"))
  assert_eq(s.get(0, 6).unwrap().value(), Number(3.0))
  let m = w.sheet(1).unwrap()
  assert_eq(m.merge_span(0, 0), Some((2, 2)))
  for (r, c) in [(0, 1), (1, 0), (1, 1)] {
    assert_true(m.is_covered(r, c))
  }
  assert_eq(m.get(1, 2).unwrap().value(), Number(42.0))
  s.set(1, 0, Cell::new(Number(8.5)))
  let reread = read_ods(w.to_ods(), allow_formatting_loss=true).workbook()
  assert_eq(reread.sheet(0).unwrap().get(1, 0).unwrap().value(), Number(8.5))
  assert_eq(reread.sheet(0).unwrap().get(2, 0).unwrap().value(), Number(7.5))
  assert_eq(
    reread.sheet(0).unwrap().get(0, 3).unwrap().value(),
    Text(" leading \t中\n文 "),
  )
  assert_eq(reread.sheet(1).unwrap().merge_span(0, 0), Some((2, 2)))
  assert_true(
    imported
    .diagnostics()
    .iter()
    .any(d => {
      d.code == "FORMULA_CACHE_NOT_RECALCULATED" && d.row == 0 && d.col == 6
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
fn reader_xml_fixture(body : String) -> String {
  "<o:document-content xmlns:o=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:t=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:x=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"><o:body><o:spreadsheet><t:table t:name=\"Input\">\{body}</t:table></o:spreadsheet></o:body></o:document-content>"
}

///|
fn reader_xml_rejects(xml : String) -> Bool {
  try {
    import_content(xml) |> ignore
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "reject semantic losses and malformed merge coverage with cell coordinates" {
  for
    cell in [
      "<t:table-cell o:value-type=\"currency\" o:value=\"5\"/>", "<t:table-cell o:value-type=\"date\" o:date-value=\"2024-01-01T01:00:00\"/>",
      "<t:table-cell><x:p>untyped</x:p></t:table-cell>", "<t:table-cell o:value-type=\"float\" o:value=\"5\" o:boolean-value=\"true\"/>",
      "<t:covered-table-cell/>", "<t:table-cell o:value-type=\"string\"><x:p><x:a>link</x:a></x:p></t:table-cell>",
      "<t:table-cell t:number-columns-spanned=\"2\"/>",
    ] {
    assert_true(
      reader_xml_rejects(
        reader_xml_fixture("<t:table-row>\{cell}</t:table-row>"),
      ),
    )
  }
  let error = try {
    import_content(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"currency\"/></t:table-row>",
      ),
    )
    |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("sheet 'Input' row 0 col 0"))
}

///|
test "XML parser rejects duplicate expanded attributes and custom entities" {
  for
    xml in [
      "<a/><b/>", "<a>&external;</a>", "<!DOCTYPE a><a/>", "<a><![CDATA[x]]></a>",
      "<a x='1'x='2'/>", "<a xmlns:p='u' xmlns:q='u' p:x='1' q:x='2'/>", "<a>&#0;</a>",
      "<a>&#xD800;</a>", "<a><b></a></b>",
    ] {
    assert_true(
      try {
        read_xml(xml) |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "text controls expand within budgets and repeated rows are bounded" {
  let xml = reader_xml_fixture(
    "<t:table-row t:number-rows-repeated=\"2\"><t:table-cell o:value-type=\"string\" t:number-columns-repeated=\"2\"><x:p>a<x:s x:c=\"2\"/>b<x:tab/><x:line-break/>&amp;&#x4E2D;</x:p></t:table-cell></t:table-row>",
  )
  let s = import_content(xml).workbook().sheet(0).unwrap()
  for r in [0, 1] {
    for c in [0, 1] {
      assert_eq(s.get(r, c).unwrap().value(), Text("a  b\t\n&中"))
    }
  }
  assert_true(
    reader_xml_rejects(
      reader_xml_fixture(
        "<t:table-row><t:table-cell o:value-type=\"string\"><x:p><x:s x:c=\"2147483647\"/></x:p></t:table-cell></t:table-row>",
      ),
    ),
  )
}

///|
test "diagnostics cannot expand without bound and returned list is a copy" {
  let result = read_ods(
    reader_fixture("typed-prefix-alias"),
    allow_formatting_loss=true,
  )
  let copy = result.diagnostics()
  copy.clear()
  assert_eq(result.diagnostics().length(), 1)
  let xml = reader_xml_fixture(
    "<t:table-row t:number-rows-repeated=\"65\"><t:table-cell t:number-columns-repeated=\"128\" t:style-name=\"x\"/></t:table-row>",
  )
  let many = import_content(xml).diagnostics()
  assert_eq(many.filter(d => d.code == "FORMATTING_DROPPED").length(), 32)
  assert_true(
    many
    .iter()
    .any(d => {
      d.code == "FORMATTING_DROPPED_SUMMARY" &&
      d.message.contains("8288 additional occurrences")
    }),
  )
  // Non-coalesced diagnostic kinds still hit the unchanged hard budget.
  let notices = ReadNotices::new()
  for _ in 0..<8192 {
    read_notice(notices, {
      sheet: "",
      row: -1,
      col: -1,
      code: "CONTROL",
      message: "bounded",
    })
  }
  assert_true(
    try {
      read_notice(notices, {
        sheet: "",
        row: -1,
        col: -1,
        code: "CONTROL",
        message: "bounded",
      })
      false
    } catch {
      Invalid(_) => true
    },
  )
}
