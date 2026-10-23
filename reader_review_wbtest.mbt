///|
test "review rejects malformed XML declarations and raw CDATA terminator" {
  for
    xml in [
      "<?xml?><a/>", "<?xml garbage?><a/>", "<?xml version='2.0'?><a/>", "<?xml version='1.0' encoding='UTF-8' nonsense='x'?><a/>",
      "<?xml version='1.0' encoding='ISO-8859-1' note='UTF-8'?><a/>", "<a>]]></a>",
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
  // Escaped text is valid even when its decoded characters form the sequence.
  read_xml("<?xml version='1.0' encoding='UTF-8'?><a>]]&gt;</a>") |> ignore
}

///|
test "review validates local XML QName components" {
  for
    xml in [
      "<a xmlns:p='u'><p:1bad/></a>", "<a xmlns:p='u' p:1bad='x'/>", "<a xmlns:p='u'><p:-bad/></a>",
      "<a xmlns:p='u'><p:.bad/></a>", "<a xmlns:1bad='u'/>", "<a xmlns:p='http://www.w3.org/2000/xmlns/'/>",
      "<a xmlns:p='http://www.w3.org/XML/1998/namespace'/>",
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
  read_xml("<a xmlns:p='u'><p:_good p:good='x'/></a>") |> ignore
}

///|
test "review rejects LibreOffice error cache instead of converting to string" {
  let xml = reader_xml_fixture(
    "<t:table-row><t:table-cell xmlns:ce=\"urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0\" o:value-type=\"string\" ce:value-type=\"error\"><x:p>#DIV/0!</x:p></t:table-cell></t:table-row>",
  )
  assert_true(reader_xml_rejects(xml))
  let mismatch = reader_xml_fixture(
    "<t:table-row><t:table-cell xmlns:ce=\"urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0\" o:value-type=\"float\" ce:value-type=\"string\" o:value=\"1\"/></t:table-row>",
  )
  assert_true(reader_xml_rejects(mismatch))
}

///|
test "review preserves declared columns and explicit empty trailing rows" {
  let xml = reader_xml_fixture(
    "<t:table-column t:number-columns-repeated=\"4\"/><t:table-row t:number-rows-repeated=\"3\"/>",
  )
  let sheet = import_content(xml).workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions(), (3, 4))
}

///|
fn review_book_xml(tables : String) -> String {
  "<o:document-content xmlns:o=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:t=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:x=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"><o:body><o:spreadsheet>\{tables}</o:spreadsheet></o:body></o:document-content>"
}

///|
test "review rejects aggregate repeated text and grid expansion budgets" {
  let tables = StringBuilder()
  for i in 0..<3 {
    tables.write_string(
      "<t:table t:name=\"S\{i}\"><t:table-row t:number-rows-repeated=\"2\"><t:table-cell t:number-columns-repeated=\"32\" o:value-type=\"string\"><x:p><x:s x:c=\"32767\"/></x:p></t:table-cell></t:table-row></t:table>",
    )
  }
  assert_true(reader_xml_rejects(review_book_xml(tables.to_string())))
  let grids = StringBuilder()
  for i in 0..<5 {
    grids.write_string(
      "<t:table t:name=\"G\{i}\"><t:table-row t:number-rows-repeated=\"512\"><t:table-cell t:number-columns-repeated=\"128\"/></t:table-row></t:table>",
    )
  }
  assert_true(reader_xml_rejects(review_book_xml(grids.to_string())))
}

///|
test "review repeat overflow reports known sheet and cell location" {
  let xml = reader_xml_fixture(
    "<t:table-row><t:table-cell t:number-columns-repeated=\"129\"/></t:table-row>",
  )
  let error = try {
    import_content(xml) |> ignore
    ""
  } catch {
    Invalid(message) => message
  }
  assert_true(error.contains("Input"))
  assert_true(error.contains("row 0"))
  assert_true(error.contains("col 0"))
}

///|
test "review merge extent cannot shrink below anchor span" {
  let truncated = reader_xml_fixture(
    "<t:table-row><t:table-cell t:number-rows-spanned=\"3\"/></t:table-row><t:table-row><t:covered-table-cell/></t:table-row>",
  )
  assert_true(reader_xml_rejects(truncated))
  let complete = reader_xml_fixture(
    "<t:table-row><t:table-cell t:number-rows-spanned=\"3\"/></t:table-row><t:table-row t:number-rows-repeated=\"2\"><t:covered-table-cell/></t:table-row>",
  )
  let sheet = import_content(complete).workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions(), (3, 1))
  assert_eq(sheet.merge_span(0, 0), Some((3, 1)))
}

///|
test "review XML declaration cannot contain entity references" {
  for
    xml in [
      "<?xml version='1.&#48;'?><a/>", "<?xml version='1.0' encoding='UTF&#x2D;8'?><a/>",
      "<?xml version='1.0' standalone='y&#101;s'?><a/>",
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
test "review ODF numbers reject language-only syntax" {
  for
    raw in [
      "1_000", "0x10", "1e", "1e+", "--1", "1.2.3", "NaN", "INF", "-INF", "1e9999",
    ] {
    assert_true(
      reader_xml_rejects(
        reader_xml_fixture(
          "<t:table-row><t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/></t:table-row>",
        ),
      ),
    )
  }
  for
    (raw, value) in [
      (".5", 0.5),
      ("1.", 1.0),
      ("-1.25e2", -125.0),
      ("+1E+2", 100.0),
    ] {
    assert_eq(read_finite_double(raw), value)
  }
}
