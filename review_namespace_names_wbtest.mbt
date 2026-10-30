///|
test "namespace NCName contexts reject colon without breaking element QNames" {
  for
    xml in [
      "<?a:b?><r/>", "<!DOCTYPE r [<?a:b?>]><r/>", "<!DOCTYPE r [<!ENTITY a:b 'x'>]><r/>",
      "<!DOCTYPE r [<!ENTITY % a:b ' '>]><r/>", "<!DOCTYPE r [%a:b;]><r/>", "<!DOCTYPE r [<!NOTATION a:b SYSTEM 'urn:x'>]><r/>",
      "<!DOCTYPE r [<!ENTITY e SYSTEM 'urn:x' NDATA a:b>]><r/>", "<!DOCTYPE r [<!ATTLIST r n NOTATION (a:b) #IMPLIED>]><r/>",
      "<!DOCTYPE r SYSTEM 'urn:x'><r>&a:b;</r>", "<!DOCTYPE r [<!ENTITY e '&a:b;'>]><r/>",
      "<!DOCTYPE a:b:c><r/>", "<!DOCTYPE r [<!ELEMENT a:b:c EMPTY>]><r/>", "<!DOCTYPE r [<!ELEMENT r (a:b:c)>]><r/>",
      "<!DOCTYPE r [<!ATTLIST a:b:c x CDATA #IMPLIED>]><r/>", "<!DOCTYPE r [<!ATTLIST r a:b:c CDATA #IMPLIED>]><r/>",
    ] {
    assert_true(reader_xml_rejects(xml))
  }
  ignore(
    read_xml(
      "<!DOCTYPE p:r [<!ELEMENT p:r EMPTY><!ATTLIST p:r p:x CDATA #IMPLIED>]><p:r xmlns:p='urn:x' p:x='ok'/>",
    ),
  )
  ignore(
    read_xml(
      "<!DOCTYPE r [<!ELEMENT unused:p EMPTY><!ATTLIST unused:p v:x CDATA #IMPLIED>]><r/>",
    ),
  )
  ignore(
    read_xml(
      "<!DOCTYPE r [<!ATTLIST r token (a:b|:|a:b:c) #IMPLIED>]><r token='a:b'/>",
    ),
  )
  ignore(
    read_xml(
      "<!DOCTYPE r [<!ATTLIST r token NMTOKEN #IMPLIED>]><r token='a:b:c'/>",
    ),
  )
}
