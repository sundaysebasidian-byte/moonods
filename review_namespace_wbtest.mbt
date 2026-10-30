///|
test "explicit reserved xml binding is valid and matches implicit binding" {
  let implicit = read_xml("<a xml:lang='en'/>")
  let explicit = read_xml(
    "<a xmlns:xml='http://www.w3.org/XML/1998/namespace' xml:lang='en'/>",
  )
  assert_eq(implicit.attrs, explicit.attrs)
  ignore(
    read_xml(
      "<a xmlns:xml='http://www.w3.org/XML/1998/namespace'><b xmlns:xml='http://www.w3.org/XML/1998/namespace'/></a>",
    ),
  )
  ignore(read_xml("<a xmlns:xmlExtra='urn:example' xmlExtra:x='1'/>"))
}

///|
test "reserved namespaces cannot be rebound or appropriated" {
  for
    xml in [
      "<a xmlns:xml='urn:wrong'/>", "<a xmlns:xml=''/>", "<a xmlns:p='http://www.w3.org/XML/1998/namespace'/>",
      "<a xmlns='http://www.w3.org/XML/1998/namespace'/>", "<a xmlns:xmlns='http://www.w3.org/2000/xmlns/'/>",
      "<a xmlns:p='http://www.w3.org/2000/xmlns/'/>", "<a xmlns='http://www.w3.org/2000/xmlns/'/>",
      "<xmlns:a/>",
    ] {
    let rejected = try {
      ignore(read_xml(xml))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
}
