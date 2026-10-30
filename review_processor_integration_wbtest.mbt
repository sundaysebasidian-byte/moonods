///|
fn integration_text(node : ReadElement) -> String {
  let b = StringBuilder()
  for part in node.parts {
    match part {
      ReadText(s) => b.write_string(s)
      ReadElement(e) => b.write_string(integration_text(e))
    }
  }
  b.to_string()
}

///|
test "integrated DTD markup entity defaults and namespace inheritance" {
  let root = read_xml(
    "<!DOCTYPE r [<!ENTITY inner '<p:x>hello</p:x>'><!ENTITY outer '&inner;!'><!ATTLIST r xmlns:p CDATA 'urn:test' words NMTOKENS ' a   b '>]><r>&outer;</r>",
  )
  assert_eq(root.attrs.get("words"), Some("a b"))
  assert_eq(integration_text(root), "hello!")
  assert_true(root.parts[0] is ReadElement(e) && e.name == "urn:test#x")
  assert_eq(
    integration_text(
      read_xml("<!DOCTYPE a [<!ENTITY e '&#xD;&#xA;'>]><a>&e;</a>"),
    ),
    "\r\n",
  )
  assert_eq(integration_text(read_xml("<a>&#xD;&#xA;</a>")), "\r\n")
  assert_eq(
    integration_text(
      read_xml("<!DOCTYPE a [<!ENTITY e '&#60;b/> '>]><a>&e;</a>"),
    ),
    " ",
  )
  assert_eq(integration_text(read_xml("<a>&#60;b/></a>")), "<b/>")
}

///|
test "integrated DTD entity boundaries recursion external and undeclared refuse" {
  for
    xml in [
      "<!DOCTYPE a [<!ENTITY e '<b>'>]><a>&e;</b></a>", "<!DOCTYPE a [<!ENTITY e '</b>'>]><a><b>&e;</a>",
      "<!DOCTYPE a [<!ENTITY e '&e;'>]><a>&e;</a>", "<!DOCTYPE a [<!ENTITY e '&f;'><!ENTITY f '&e;'>]><a>&e;</a>",
      "<!DOCTYPE a [<!ENTITY e SYSTEM 'file:///not-read'>]><a>&e;</a>", "<!DOCTYPE a [<!ENTITY e SYSTEM 'https://example.invalid/no-network'>]><a x='&e;'/>",
      "<!DOCTYPE a [<!ENTITY e '&missing;'>]><a>&e;</a>",
    ] {
    assert_true(reader_xml_rejects(xml))
  }
  ignore(read_xml("<!DOCTYPE a [<!ENTITY e '&e;'>]><a/>"))
  ignore(read_xml("<!DOCTYPE a SYSTEM 'https://example.invalid/not-read'><a/>"))
}

///|
test "integrated xml id declaration diagnostic without instance and defaults" {
  let assigned : Array[XmlIdAssignment] = []
  let errors : Array[XmlIdDiagnostic] = []
  ignore(
    read_xml(
      "<!DOCTYPE a [<!ATTLIST unused xml:id CDATA #IMPLIED><!ATTLIST a xml:id ID '  chosen  '>]><a/>",
      document_part="content.xml",
      id_assignments=assigned,
      id_diagnostics=errors,
    ),
  )
  assert_eq(assigned.length(), 1)
  assert_eq(assigned[0].value, "chosen")
  assert_eq(assigned[0].declared_type, Some("ID"))
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].element_index, -1)
  assert_eq(errors[0].code, "XML_ID_DECLARATION_TYPE")
}

///|
test "public import exposes nonfatal xml id metadata independently of notices" {
  let content = reader_xml_fixture(
    "<t:table-row xml:id='same'><t:table-cell xml:id='same' o:value-type='string'><x:p xml:id='1bad'>ok</x:p></t:table-cell></t:table-row>",
  )
  let result = import_content(content)
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text("ok"),
  )
  assert_eq(result.xml_ids().length(), 3)
  assert_eq(result.xml_id_diagnostics().length(), 3)
  let copy = result.xml_ids()
  copy.clear()
  assert_eq(result.xml_ids().length(), 3)
  let errors = result.xml_id_diagnostics()
  errors.clear()
  assert_eq(result.xml_id_diagnostics().length(), 3)
}

///|
test "DTD parameter entity cutoff and standalone declaration adoption" {
  let before = "<!DOCTYPE r [<!ENTITY % ignored ' '>%ignored;<!ATTLIST r flag CDATA 'yes'>]><r/>"
  assert_eq(read_xml(before).attrs.get("flag"), None)
  assert_eq(
    read_xml("<?xml version='1.0' standalone='yes'?>" + before).attrs.get(
      "flag",
    ),
    Some("yes"),
  )
}

///|
test "expanded content and repeated default attributes are globally bounded" {
  let large = StringBuilder()
  for _ in 0..<16000 {
    large.write_char('x')
  }
  let xml = StringBuilder()
  xml.write_string(
    "<!DOCTYPE r [<!ENTITY big '" + large.to_string() + "'>]><r>",
  )
  for _ in 0..<70 {
    xml.write_string("&big;")
  }
  xml.write_string("</r>")
  assert_true(reader_xml_rejects(xml.to_string()))
  let attrs = StringBuilder()
  attrs.write_string(
    "<!DOCTYPE r [<!ATTLIST child default CDATA '" +
    large.to_string() +
    "'>]><r>",
  )
  for _ in 0..<70 {
    attrs.write_string("<child/>")
  }
  attrs.write_string("</r>")
  assert_true(reader_xml_rejects(attrs.to_string()))
}

///|
test "public package XML IDs have independent document scopes" {
  let content = reader_xml_fixture(
    "<t:table-row xml:id='shared'><t:table-cell o:value-type='string'><x:p>ok</x:p></t:table-cell></t:table-row>",
  )
  let manifest = test_minimal_manifest().replace(
    old="<m:manifest ",
    new="<m:manifest xml:id='shared' ",
  )
  let result = read_ods(
    stored_package([
      ("mimetype", @utf8.encode(media_type[:])),
      ("content.xml", @utf8.encode(content[:])),
      ("META-INF/manifest.xml", @utf8.encode(manifest[:])),
    ]),
    allow_formatting_loss=true,
  )
  assert_eq(result.xml_ids().length(), 2)
  assert_eq(result.xml_id_diagnostics().length(), 0)
  for id in result.xml_ids() {
    assert_true(id.unique)
  }
}

///|
test "entity markup attributes preserve two replacement whitespace characters" {
  let root = read_xml(
    "<!DOCTYPE a [<!ENTITY e \"<b x='&#13;&#10;'/>\">]><a>&e;</a>",
  )
  assert_true(root.parts[0] is ReadElement(e) && e.attrs.get("x") == Some("  "))
}
