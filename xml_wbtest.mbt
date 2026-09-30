test "XML escapes every attribute and preserves whitespace" {
  assert_eq(xml_escape("中文<&>\"'\n\r\t"), "中文&lt;&amp;&gt;&quot;&apos;&#10;&#13;&#9;")
  assert_eq(text_paragraph(" a  b\t\n"), "<text:p><text:s/>a<text:s/><text:s/>b<text:tab/><text:line-break/></text:p>")
  assert_true(Cell::new(Text("")).xml("").contains("office:value-type=\"string\""))
  assert_true(!Cell::new(Empty).xml("").contains("office:value-type"))
}
