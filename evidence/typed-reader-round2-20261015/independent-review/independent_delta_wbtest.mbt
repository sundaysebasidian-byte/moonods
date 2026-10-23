///|
test "independent decimal normalization cases" {
  for (a,b) in [("123.45000e-2","1.2345"),("-00000123.45E+002","-12345"),(".0000000000000000001","1e-19"),("-0e-9999","-0"),("100000000000000000000e-20","1")] {
    assert_eq(read_decimal_identity(a),read_decimal_identity(b))
  }
}
///|
test "independent precision boundaries emit accurate notices" {
  for (raw,changed) in [("9007199254740995",true),("9007199254740994",false),("1.234567890123456789",true),("4.9406564584124654e-324",true),("5e-324",false),("-0e-9999",false),("1.7976931348623157e308",false)] {
    let result=loss_case("<t:table-cell o:value-type=\"float\" o:value=\"\{raw}\"/>")
    assert_eq(result.diagnostics().iter().any(d => d.code=="NUMBER_PRECISION_CHANGED"),changed,msg=raw)
  }
}
///|
test "independent rejection of numeric caps and overflow" {
  for raw in ["1e309","-1e309","2e-324","-2e-324"] {
    assert_true(try {read_finite_double(raw)|>ignore;false} catch {Invalid(_)=>true},msg=raw)
  }
  let b=StringBuilder()
  for _ in 0..<1025 { b.write_char('0') }
  assert_true(try {read_finite_double(b.to_string())|>ignore;false} catch {Invalid(_)=>true})
}
///|
test "independent precision preview remains bounded" {
  let b=StringBuilder()
  b.write_string("1.")
  for _ in 0..<1000 { b.write_char('1') }
  let result=loss_case("<t:table-cell o:value-type=\"float\" o:value=\"\{b.to_string()}\"/>")
  assert_true(result.diagnostics().iter().any(d=>d.code=="NUMBER_PRECISION_CHANGED" && d.message.length()<250))
}
///|
test "independent repeated rounded cells get individual diagnostics" {
  let result=loss_case("<t:table-cell t:number-columns-repeated=\"3\" o:value-type=\"float\" o:value=\"9007199254740993\"/>")
  for c in 0..<3 {
    assert_true(result.diagnostics().iter().any(d=>d.code=="NUMBER_PRECISION_CHANGED" && d.col==c && d.row==0))
  }
}
///|
test "independent numeric formula caches and merged anchors retain meaning" {
  let result=loss_case("<t:table-cell xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" t:formula=\"of:=-0\" o:value-type=\"float\" o:value=\"-0\" t:number-columns-spanned=\"2\"/><t:covered-table-cell/>")
  let again=read_ods(result.workbook().to_ods(),allow_formatting_loss=true)
  let s=again.workbook().sheet(0).unwrap()
  assert_eq(s.merge_span(0,0),Some((1,2)))
  assert_true(s.is_covered(0,1))
  assert_eq(s.get(0,0).unwrap().expression(),Some("of:=-0"))
  match s.get(0,0).unwrap().value() { Number(n)=>assert_true(1.0/n<0.0); _=>fail("numeric cache lost") }
}
///|
test "independent public package loss notices match actual omitted parts" {
  let xml=reader_xml_fixture("<t:table-row><t:table-cell/></t:table-row>")
  let zip=stored_package([("mimetype",@utf8.encode(media_type[:])),("content.xml",@utf8.encode(xml[:])),("meta.xml",b"<metadata/>"),("settings.xml",b"<settings/>"),("styles.xml",b"<styles/>")])
  let result=read_ods(zip,allow_formatting_loss=true)
  for part in ["meta.xml","settings.xml","styles.xml"] {
    assert_true(result.diagnostics().iter().any(d=>d.code=="PACKAGE_PART_DROPPED" && d.message.contains(part)))
  }
  assert_false(result.diagnostics().iter().any(d=>d.code=="PACKAGE_PART_DROPPED" && d.message.contains("thumbnail")))
}
