///|
test "independent rejects merge extending beyond partial row input" {
  let xml = reader_xml_fixture("<t:table-row><t:table-cell t:number-rows-spanned=\"3\"/></t:table-row><t:table-row><t:covered-table-cell/></t:table-row>")
  assert_true(reader_xml_rejects(xml))
}

///|
test "independent rejects illegal XML declaration references" {
  assert_true(try { read_xml("<?xml version='1.&#48;'?><a/>") |> ignore; false } catch { Invalid(_) => true })
}

///|
test "independent rejects invalid numeric lexical values" {
  for raw in ["0x10", "1_000", "1.0junk", " 1 ", "1e999", "NaN", "Infinity", "-Infinity", "-nan"] {
    let xml = reader_xml_fixture("<t:table-row><t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/></t:table-row>")
    assert_true(reader_xml_rejects(xml), msg=raw)
  }
}

///|
test "independent rejects invalid calendar dates" {
  for raw in ["1900-02-29", "2023-02-29", "2024-04-31", "0000-01-01", "2024-00-01", "2024-01-00", "2024-13-01"] {
    let xml = reader_xml_fixture("<t:table-row><t:table-cell o:value-type=\"date\" o:date-value=\"\{raw}\"/></t:table-row>")
    assert_true(reader_xml_rejects(xml), msg=raw)
  }
}

///|
test "independent rejects merge truncation with trailing empty row" {
  let xml = reader_xml_fixture("<t:table-row><t:table-cell t:number-rows-spanned=\"4\"/></t:table-row><t:table-row t:number-rows-repeated=\"2\"><t:covered-table-cell/></t:table-row>")
  assert_true(reader_xml_rejects(xml))
}

///|
test "independent ZIP mutation scan returns cleanly" {
  let fixture = reader_fixture("typed-prefix-alias")
  for i in 0..<fixture.length() {
    let bytes = fixture.to_array()
    bytes[i] = (bytes[i].to_int() ^ 0x80).to_byte()
    try {
      read_ods(Bytes::from_array(bytes), allow_formatting_loss=true) |> ignore
    } catch {
      Invalid(_) => ()
    }
  }
}
