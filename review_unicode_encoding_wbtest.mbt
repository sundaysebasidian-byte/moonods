///|
test "XML fifth edition Unicode NCNames and namespace aliases" {
  let root = read_xml(
    "<表:数据 xmlns:表='urn:test' 表:名字='值'><表:𐀀/></表:数据>",
  )
  assert_eq(root.name, "urn:test#数据")
  assert_eq(root.attrs.get("urn:test#名字"), Some("值"))
  ignore(read_xml("<a·̀‿/>"))
  for
    s in [
      "<̀a/>", "<·a/>", "<:a/>", "<a:/>", "<a:b:c/>", "<a xmlns:̀x='urn:x'/>",
    ] {
    assert_true(
      try {
        ignore(read_xml(s))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "XML NameStartChar range edges and continuation-only ranges" {
  for
    n in [
      0xC0, 0xD6, 0xD8, 0xF6, 0xF8, 0x2FF, 0x370, 0x37D, 0x37F, 0x1FFF, 0x200C, 0x200D,
      0x2070, 0x218F, 0x2C00, 0x2FEF, 0x3001, 0xD7FF, 0xF900, 0xFDCF, 0xFDF0, 0xFFFD,
      0x10000, 0xEFFFF,
    ] {
    assert_true(xml_name_start(n.unsafe_to_char()))
  }
  for
    n in [
      0xB7, 0xD7, 0xF7, 0x300, 0x36F, 0x37E, 0x200B, 0x200E, 0x206F, 0x2190, 0x2BFF,
      0x2FF0, 0x3000, 0xF8FF, 0xFDD0, 0xFDEF, 0xFFFE, 0xF0000,
    ] {
    assert_false(xml_name_start(n.unsafe_to_char()))
  }
  for n in [0xB7, 0x300, 0x36F, 0x203F, 0x2040] {
    assert_true(xml_name_char(n.unsafe_to_char()))
  }
}

///|
fn test_utf16(s : String, little : Bool) -> Bytes {
  let out = @buffer.Buffer()
  out.write_byte(if little { b'\xFF' } else { b'\xFE' })
  out.write_byte(if little { b'\xFE' } else { b'\xFF' })
  for c in s {
    let n = c.to_int()
    let units = if n > 0xFFFF {
      [0xD800 + ((n - 0x10000) >> 10), 0xDC00 + ((n - 0x10000) & 0x3FF)]
    } else {
      [n]
    }
    for u in units {
      out.write_byte((if little { u & 0xFF } else { u >> 8 }).to_byte())
      out.write_byte((if little { u >> 8 } else { u & 0xFF }).to_byte())
    }
  }
  out.to_bytes()
}

///|
test "UTF16 BOM scalar decoding both endians and declaration coherence" {
  for little in [true, false] {
    let source = "<?xml version='1.0' encoding='UtF-16'?><表>中𐀀</表>"
    assert_eq(ods_xml_decode(test_utf16(source, little)), "\uFEFF" + source)
    assert_eq(read_xml(ods_xml_decode(test_utf16(source, little))).name, "#表")
    assert_eq(ods_xml_decode(test_utf16("<a/>", little)), "\uFEFF<a/>")
    let bad = "<?xml version='1.0' encoding='UTF-8'?><a/>"
    assert_true(
      try {
        ignore(ods_xml_decode(test_utf16(bad, little)))
        false
      } catch {
        Invalid(_) => true
      },
    )
    let wrong = if little { "UTF-16BE" } else { "UTF-16LE" }
    assert_true(
      try {
        ignore(
          ods_xml_decode(
            test_utf16("<?xml version='1.0' encoding='\{wrong}'?><a/>", little),
          ),
        )
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  for
    bad in [
      b"\xff\xfe\x00", b"\xff\xfe\x00\xd8", b"\xff\xfe\x00\xdc", b"\xfe\xff\xd8\x00\x00\x61",
      b"<?xml version='1.0' encoding='UTF-16'?><a/>",
    ] {
    assert_true(
      try {
        ignore(ods_xml_decode(bad))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "public ODS UTF16 content with Unicode namespace alias roundtrip" {
  let xml = "<?xml version='1.0' encoding='UTF-16'?><办:document-content xmlns:办='urn:oasis:names:tc:opendocument:xmlns:office:1.0' xmlns:表='urn:oasis:names:tc:opendocument:xmlns:table:1.0' xmlns:文='urn:oasis:names:tc:opendocument:xmlns:text:1.0' 办:version='1.3'><办:body><办:spreadsheet><表:table 表:name='数据'><表:table-row><表:table-cell 办:value-type='string'><文:p>中𐀀</文:p></表:table-cell></表:table-row></表:table></办:spreadsheet></办:body></办:document-content>"
  for little in [true, false] {
    let bytes = stored_package([
      ("mimetype", @utf8.encode(media_type[:])),
      ("content.xml", test_utf16(xml, little)),
      ("META-INF/manifest.xml", @utf8.encode(test_minimal_manifest()[:])),
    ])
    let book = read_ods(bytes, allow_formatting_loss=true).workbook()
    assert_eq(
      book.sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text("中𐀀"),
    )
    let again = read_ods(book.to_ods(), allow_formatting_loss=true).workbook()
    assert_eq(
      again.sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text("中𐀀"),
    )
  }
}

///|
test "UTF16 and UTF8 duplicate signatures are not silently stripped" {
  for little in [true, false] {
    assert_true(
      try {
        ignore(read_xml(ods_xml_decode(test_utf16("\uFEFF<a/>", little))))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  assert_true(
    try {
      ignore(read_xml(ods_xml_decode(b"\xef\xbb\xbf\xef\xbb\xbf<a/>")))
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "single BOM accepted while in-content FEFF preserved across encodings" {
  for
    bytes in [
      test_utf16("<a>\uFEFF中</a>", true),
      test_utf16("<a>\uFEFF中</a>", false),
      @utf8.encode("\uFEFF<a>\uFEFF中</a>"[:]),
    ] {
    let root = read_xml(ods_xml_decode(bytes))
    assert_true(root.parts[0] is ReadText("\uFEFF中"))
  }
}

///|
test "OpenFormula Unicode NCName prefix normalized without altering body" {
  let ns = {
    "算": "urn:oasis:names:tc:opendocument:xmlns:of:1.2",
    "a·̀": "urn:oasis:names:tc:opendocument:xmlns:of:1.2",
  }
  assert_eq(read_formula_prefix("算:=1+1", ns), "of:=1+1")
  assert_eq(read_formula_prefix("a·̀:=\"算:=\"", ns), "of:=\"算:=\"")
  for f in ["̀算:=1", "missing:=1", "算:1", "算:=", "算:算:=1"] {
    assert_true(
      try {
        ignore(read_formula_prefix(f, ns))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
fn test_minimal_manifest() -> String {
  "<m:manifest xmlns:m='urn:oasis:names:tc:opendocument:xmlns:manifest:1.0' m:version='1.3'><m:file-entry m:full-path='/' m:media-type='application/vnd.oasis.opendocument.spreadsheet'/><m:file-entry m:full-path='content.xml' m:media-type='text/xml'/></m:manifest>"
}
