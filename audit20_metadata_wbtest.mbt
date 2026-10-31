///|
test "audit20 ids duplicate scope across three real package parts" {
  let content = reader_xml_fixture(
    "<t:table-row xml:id='shared'><t:table-cell xml:id='shared' o:value-type='string'><x:p>kept</x:p></t:table-cell></t:table-row>",
  )
  let manifest = test_minimal_manifest()
    .replace(old="<m:manifest ", new="<m:manifest xml:id='shared' ")
    .replace(
      old="</m:manifest>",
      new="<m:file-entry m:full-path='meta.xml' m:media-type='text/xml'/></m:manifest>",
    )
  let meta = "<o:document-meta xmlns:o='urn:oasis:names:tc:opendocument:xmlns:office:1.0' xml:id='shared'><o:meta/></o:document-meta>"
  let result = read_ods(
    stored_package([
      ("mimetype", @utf8.encode(media_type[:])),
      ("content.xml", @utf8.encode(content[:])),
      ("META-INF/manifest.xml", @utf8.encode(manifest[:])),
      ("meta.xml", @utf8.encode(meta[:])),
    ]),
    allow_formatting_loss=true,
  )
  let ids = result.xml_ids()
  assert_eq(ids.length(), 4)
  assert_eq(
    ids.filter(x => x.document_part == "content.xml" && !x.unique).length(),
    2,
  )
  assert_eq(
    ids.filter(x => x.document_part != "content.xml" && x.unique).length(),
    2,
  )
  assert_eq(result.xml_id_diagnostics().length(), 2)
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text("kept"),
  )
  let errors = result.xml_id_diagnostics()
  errors.clear()
  ids.clear()
  assert_eq(result.xml_ids().length(), 4)
  assert_eq(result.xml_id_diagnostics().length(), 2)
}

///|
test "audit20 id normalization duplicate followed by independent next parse" {
  let ids : Array[XmlIdAssignment] = []
  let errors : Array[XmlIdDiagnostic] = []
  ignore(
    read_xml(
      "<!DOCTYPE r [<!ATTLIST r xml:id ID 'same'>]><r><a xml:id=' same '/><b xml:id='&#x9;same'/></r>",
      document_part="first.xml",
      id_assignments=ids,
      id_diagnostics=errors,
    ),
  )
  assert_eq(ids.length(), 3)
  assert_eq(ids.filter(x => !x.unique).length(), 2)
  assert_eq(ids.filter(x => !x.valid_ncname).length(), 1)
  ignore(
    read_xml(
      "<r xml:id='same'/>",
      document_part="second.xml",
      id_assignments=ids,
      id_diagnostics=errors,
    ),
  )
  assert_eq(ids.length(), 4)
  assert_true(ids[3].unique)
  assert_eq(ids[3].document_part, "second.xml")
  assert_eq(errors.filter(x => x.document_part == "second.xml").length(), 0)
}

///|
test "audit20 events appended collector and nested replacement order" {
  let events : Array[XmlProcessorEvent] = []
  ignore(
    read_xml(
      "<?old first?><old/>",
      document_part="old.xml",
      processor_events=events,
    ),
  )
  ignore(
    read_xml(
      "<?pre a?><!DOCTYPE r [<?dtd b?><!ENTITY inner '<?inner i?>'><!ENTITY outer '<?outer o?>&inner;'>]><r>&outer;<?after z?></r><?end e?>",
      document_part="new.xml",
      processor_events=events,
    ),
  )
  assert_eq(events.map(x => x.name), [
    "old", "pre", "dtd", "outer", "inner", "after", "end",
  ])
  for i, e in events {
    assert_eq(e.sequence, i)
  }
  assert_eq(events[0].document_part, "old.xml")
  for i in 1..<events.length() {
    assert_eq(events[i].document_part, "new.xml")
  }
  assert_eq(events.map(x => x.location), [
    "prolog", "prolog", "dtd", "content", "content", "content", "epilog",
  ])
}

///|
test "audit20 events same result accessors cannot mutate collector" {
  let result = import_content(
    "<?one a?><?two b?>" +
    reader_xml_fixture("<t:table-row><t:table-cell/></t:table-row>"),
  )
  let a = result.xml_events()
  let b = result.xml_events()
  a[0] = a[1]
  b.clear()
  assert_eq(result.xml_events().map(x => x.name), ["one", "two"])
  assert_eq(result.xml_events().map(x => x.sequence), [0, 1])
}

///|
test "audit20 DTD late default adopts only with standalone" {
  let body = "<!DOCTYPE r [<!ATTLIST r early NMTOKENS ' a   b '><!ENTITY % skip 'unused'>%skip;<!ATTLIST r late CDATA 'chosen'><!ENTITY late 'L'>]><r early=' x   y '/>"
  let no = read_xml(body)
  assert_eq(no.attrs.get("early"), Some("x y"))
  assert_eq(no.attrs.get("late"), None)
  let yes = read_xml("<?xml version='1.0' standalone='yes'?>" + body)
  assert_eq(yes.attrs.get("early"), Some("x y"))
  assert_eq(yes.attrs.get("late"), Some("chosen"))
  let explicit = read_xml(
    "<?xml version='1.0' standalone='yes'?>" +
    body.replace(old="early=' x   y '", new="early=' x   y ' late='explicit'"),
  )
  assert_eq(explicit.attrs.get("late"), Some("explicit"))
}

///|
test "audit20 DTD unread late entity classification standalone split" {
  let body = "<!DOCTYPE r [<!ENTITY % skip 'unused'>%skip;<!ENTITY later 'ok'>]><r>&later;</r>"
  let err = try {
    ignore(read_xml(body))
    Invalid("unexpected success")
  } catch {
    e => e
  }
  assert_true(err.is_unread_xml_dependency())
  assert_eq(
    integration_text(read_xml("<?xml version='1.0' standalone='yes'?>" + body)),
    "ok",
  )
}

///|
test "audit20 DTD declared fixed does not pretend validity checking" {
  let root = read_xml(
    "<!DOCTYPE r [<!ATTLIST r a CDATA #FIXED 'default' words NMTOKENS #FIXED ' a  b '>]><r a='explicit' words=' x   y '/>",
  )
  assert_eq(root.attrs.get("a"), Some("explicit"))
  assert_eq(root.attrs.get("words"), Some("x y"))
}
