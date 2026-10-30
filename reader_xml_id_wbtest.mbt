///|
test "xml id assignment normalization and Unicode NCName" {
  let root = read_xml(
    "<root xml:id='  名字  '><child xml:id='𐀀_a·̀‿'/></root>",
  )
  let report = process_xml_ids(root, document_part="content.xml")
  assert_eq(report.assignments.length(), 2)
  assert_eq(report.errors.length(), 0)
  let item = report.assignments[0]
  assert_eq(item.document_part, "content.xml")
  assert_eq(item.element_index, 0)
  assert_eq(item.value, "名字")
  assert_eq(item.attribute_type, "ID")
  assert_eq(item.declared_type, None)
  assert_eq(root.attrs.get(xml_id_expanded_name), Some("名字"))
  assert_eq(report.assignments[1].element_index, 1)
  assert_true(item.valid_ncname && item.unique)
}

///|
test "xml id duplicate values report both first and subsequent assignments" {
  let root = read_xml(
    "<r xml:id='same'><x/><x xml:id=' same '/><x xml:id='same'/></r>",
  )
  let report = process_xml_ids(root)
  assert_eq(report.assignments.length(), 3)
  assert_eq(report.errors.length(), 3)
  assert_eq(report.assignments[1].element_index, 2)
  for item in report.assignments {
    assert_eq(item.attribute_type, "ID")
    assert_true(item.valid_ncname)
    assert_false(item.unique)
  }
  for error in report.errors {
    assert_eq(error.code, "XML_ID_DUPLICATE")
  }
}

///|
test "xml id invalid values are assigned and diagnosed without fatal rejection" {
  for
    value in [
      "", "   ", "123", "a:b", "a b", "\tname", "name\n", "\rname", "󰀀",
    ] {
    let root = read_xml("<r/>")
    root.attrs.set(xml_id_expanded_name, value)
    let report = process_xml_ids(root)
    assert_eq(report.assignments.length(), 1)
    assert_eq(report.assignments[0].attribute_type, "ID")
    assert_false(report.assignments[0].valid_ncname)
    assert_eq(report.errors[0].code, "XML_ID_INVALID_NCNAME")
  }
}

///|
test "xml id literal whitespace differs from character reference whitespace" {
  let literal = process_xml_ids(read_xml("<r xml:id=' \t\n\rname \t'/>"))
  assert_eq(literal.assignments[0].value, "name")
  assert_eq(literal.errors.length(), 0)
  for reference in ["&#x9;", "&#xA;", "&#xD;"] {
    let report = process_xml_ids(read_xml("<r xml:id='\{reference}name'/>"))
    assert_false(report.assignments[0].valid_ncname)
    assert_eq(report.errors[0].code, "XML_ID_INVALID_NCNAME")
  }
  assert_eq(xml_id_normalize("  a   b  "), "a b")
}

///|
test "xml id checks supplied declared types without confusing assignment with validation" {
  let root = read_xml("<r xml:id='one'/>")
  let wrong = process_xml_ids(
    root,
    declared_types=Map([((0, xml_id_expanded_name), "CDATA")]),
  )
  assert_eq(wrong.assignments[0].attribute_type, "ID")
  assert_eq(wrong.assignments[0].declared_type, Some("CDATA"))
  assert_eq(wrong.errors[0].code, "XML_ID_DECLARED_TYPE")
  let correct = process_xml_ids(
    root,
    declared_types=Map([((0, xml_id_expanded_name), "ID")]),
  )
  assert_eq(correct.errors.length(), 0)
}

///|
test "xml id uniqueness includes explicitly supplied other ID typed attributes" {
  let root = read_xml("<r xml:id='same'><x id='same'/></r>")
  let no_declaration = process_xml_ids(root)
  assert_true(no_declaration.assignments[0].unique)
  let declared = process_xml_ids(root, other_ids=[(1, "id", "same")])
  assert_false(declared.assignments[0].unique)
  assert_eq(declared.errors[0].code, "XML_ID_DUPLICATE")
  let same_attribute = process_xml_ids(root, other_ids=[
    (0, xml_id_expanded_name, "same"),
  ])
  assert_true(same_attribute.assignments[0].unique)
}

///|
test "xml id scope is per XML document and no Unicode normalization is invented" {
  let first = process_xml_ids(
    read_xml("<r xml:id='a'/>"),
    document_part="content.xml",
  )
  let second = process_xml_ids(
    read_xml("<r xml:id='a'/>"),
    document_part="styles.xml",
  )
  assert_true(first.assignments[0].unique && second.assignments[0].unique)
  let separate = process_xml_ids(
    read_xml(
      "<r><x xml:id='é'/><x xml:id='é'/><x xml:id='a'/><x xml:id='A'/></r>",
    ),
  )
  assert_eq(separate.errors.length(), 0)
  assert_eq(separate.assignments.length(), 4)
}

///|
test "xml id absent or unqualified id does not create assignment" {
  let report = process_xml_ids(read_xml("<r id='not-xml-id'><child/></r>"))
  assert_eq(report.assignments.length(), 0)
  assert_eq(report.errors.length(), 0)
}
