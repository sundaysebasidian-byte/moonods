///|
test "XML PI instructions exposed in prolog DTD content entity and epilog order" {
  let events : Array[XmlProcessorEvent] = []
  ignore(
    read_xml(
      "<?first hello\r\nworld?><!DOCTYPE a [<?inside dtd?><!ENTITY e '<?replacement yes?>'>]><a><?body x?>&e;</a><?last?>",
      processor_events=events,
      document_part="test.xml",
    ),
  )
  let pis = events.filter(e => e.kind == "PROCESSING_INSTRUCTION")
  assert_eq(pis.map(e => e.name), [
    "first", "inside", "body", "replacement", "last",
  ])
  assert_eq(pis.map(e => e.location), [
    "prolog", "dtd", "content", "content", "epilog",
  ])
  assert_eq(pis[0].data, "hello\nworld")
  assert_eq(pis[4].data, "")
  for i, e in pis {
    assert_eq(e.sequence, i)
    assert_eq(e.document_part, "test.xml")
  }
}

///|
test "XML notation and unparsed entity identifiers are delivered without fetch" {
  let events : Array[XmlProcessorEvent] = []
  ignore(
    read_xml(
      "<!DOCTYPE a [<!NOTATION image PUBLIC 'public-id' 'https://example.invalid/type'><!ENTITY photo SYSTEM 'file:///never-open' NDATA image><!ATTLIST a asset ENTITY #IMPLIED>]><a asset='photo'/>",
      processor_events=events,
    ),
  )
  let n = events.filter(e => e.kind == "NOTATION_DECLARATION")
  assert_eq(n.length(), 1)
  assert_eq(n[0].name, "image")
  assert_eq(n[0].public_id, Some("public-id"))
  assert_eq(n[0].system_id, Some("https://example.invalid/type"))
  let e = events.filter(e => e.kind == "UNPARSED_ENTITY_DECLARATION")
  assert_eq(e.length(), 1)
  assert_eq(e[0].name, "photo")
  assert_eq(e[0].system_id, Some("file:///never-open"))
  assert_eq(e[0].notation, Some("image"))
}

///|
test "recognized unread external content is classified unsupported not malformed" {
  let error = try {
    ignore(
      read_xml(
        "<!DOCTYPE a [<!ENTITY e SYSTEM 'https://example.invalid/no-fetch'>]><a>&e;</a>",
      ),
    )
    Invalid("unexpected success")
  } catch {
    e => e
  }
  assert_true(error.is_unread_xml_dependency())
  let syntax = try {
    ignore(read_xml("<a></b>"))
    Invalid("unexpected success")
  } catch {
    e => e
  }
  assert_false(syntax.is_unread_xml_dependency())
}

///|
test "public import exposes processing instructions and protects event array" {
  let result = import_content(
    "<?application keep?>" +
    reader_xml_fixture("<t:table-row><t:table-cell/></t:table-row>"),
  )
  assert_eq(result.xml_events().length(), 1)
  assert_eq(result.xml_events()[0].name, "application")
  let copy = result.xml_events()
  copy.clear()
  assert_eq(result.xml_events().length(), 1)
}

///|
test "unread external subset records identifiers on successful bounded import" {
  let events : Array[XmlProcessorEvent] = []
  ignore(
    read_xml(
      "<!DOCTYPE a PUBLIC 'public-id' 'https://example.invalid/subset'><a/>",
      processor_events=events,
    ),
  )
  assert_eq(events[0].kind, "EXTERNAL_SUBSET_NOT_READ")
  assert_eq(events[0].public_id, Some("public-id"))
  assert_eq(events[0].system_id, Some("https://example.invalid/subset"))
}

///|
test "standalone undeclared entity is a wellformedness error not unread dependency" {
  let error = try {
    ignore(
      read_xml(
        "<?xml version='1.0' standalone='yes'?><!DOCTYPE a SYSTEM 'https://example.invalid/subset'><a>&missing;</a>",
      ),
    )
    Invalid("unexpected success")
  } catch {
    e => e
  }
  assert_false(error.is_unread_xml_dependency())
}
