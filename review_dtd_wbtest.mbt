///|
fn dtd_test_parse(
  source : String,
  standalone~ : Bool = false,
) -> DtdInfo raise OdsError {
  let chars : Array[Char] = []
  for c in source {
    chars.push(c)
  }
  let (info, end) = read_xml_dtd_prefix(chars, 0, standalone)
  if end != chars.length() {
    raise Invalid("test has trailing bytes")
  }
  info
}

///|
test "DTD declaration grammar and normalized defaults" {
  let info = dtd_test_parse(
    "<!DOCTYPE r [<!ELEMENT r (a,(b|c)*)><!ELEMENT a (#PCDATA)><!ELEMENT b EMPTY><!ELEMENT c ANY><!ENTITY value 'hello'><!ATTLIST r plain CDATA '&value;  x' tokens NMTOKENS '  a   b  ' needed ID #REQUIRED absent CDATA #IMPLIED fixed CDATA #FIXED 'z'><!NOTATION image PUBLIC 'image/png'><!ENTITY picture SYSTEM 'urn:image' NDATA image>]>",
  )
  assert_eq(info.root_name, "r")
  assert_eq(info.attributes.length(), 5)
  assert_eq(info.attributes[0].default_value, Some("hello  x"))
  assert_eq(info.attributes[1].default_value, Some("a b"))
  assert_eq(info.attributes[2].default_value, None)
  assert_eq(info.attributes[4].default_value, Some("z"))
  assert_eq(info.notations.get("image"), Some((Some("image/png"), None)))
  assert_true(info.attributes[1].tokenized)
  assert_eq(info.attributes[2].declared_type, "ID")
  match info.entities.get("picture") {
    Some(External(public_id, system_id, notation)) => {
      assert_eq(public_id, None)
      assert_eq(system_id, "urn:image")
      assert_eq(notation, Some("image"))
    }
    _ => fail("expected external entity declaration")
  }
}

///|
test "DTD first binding wins and unread PE declaration cutoff" {
  let source = "<!DOCTYPE r SYSTEM 'urn:no-fetch' [<!ENTITY x 'first'><!ENTITY x 'second'><!ATTLIST r a CDATA 'first'><!ATTLIST r a CDATA 'second'><!ENTITY % p 'not read'>%p;<!ENTITY y 'late'><!ATTLIST r b CDATA 'late'>]>"
  let no = dtd_test_parse(source)
  assert_true(no.external_subset)
  assert_true(no.unread_parameter_entity)
  assert_eq(dtd_normalize_attribute(no, "&x;", false), "first")
  assert_false(no.entities.contains("y"))
  assert_eq(no.attributes.length(), 1)
  let yes = dtd_test_parse(source, standalone=true)
  assert_true(yes.entities.contains("y"))
  assert_eq(yes.attributes.length(), 2)
}

///|
test "DTD character reference layer and whitespace" {
  let info = dtd_test_parse(
    "<!DOCTYPE r [<!ENTITY tab '&#9;'><!ENTITY ampersand '&#38;amp;'><!ENTITY rawmarkup '&#60;a/>'>]>",
  )
  assert_eq(dtd_normalize_attribute(info, "a\r\nb\tc", false), "a b c")
  assert_eq(dtd_normalize_attribute(info, "a&#9;b", false), "a\tb")
  assert_eq(dtd_normalize_attribute(info, "a&tab;b", false), "a b")
  assert_eq(dtd_normalize_attribute(info, "&ampersand;", false), "&")
  assert_true(
    try {
      ignore(dtd_normalize_attribute(info, "&rawmarkup;", false))
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "DTD malformed declarations rejected without broad skipping" {
  for
    text in [
      "<!DOCTYPE r [<!ELEMENT r (a|b,c)>]>", "<!DOCTYPE r [<!ELEMENT r (#PCDATA|a)>]>",
      "<!DOCTYPE r [<!ATTLIST r a BOGUS 'x'>]>", "<!DOCTYPE r [<!ATTLIST r a CDATA '&later;'><!ENTITY later 'x'>]>",
      "<!DOCTYPE r [<!ENTITY x '%p;'>]>", "<!DOCTYPE r [<!ENTITY x '&#xD800;'>]>",
      "<!DOCTYPE r [<!ENTITY x PUBLIC 'public-with-no-system'>]>", "<!DOCTYPE r [<!NOTATION n PUBLIC 'bad\tpubid'>]>",
      "<!DOCTYPE r [<![IGNORE[x]]>]>", "<!DOCTYPE r [<!-- a--b -->]>", "<!DOCTYPE r [<?XML bad?>]>",
    ] {
    assert_true(
      try {
        ignore(dtd_test_parse(text))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "DTD bounded recursive expansion rejects cycles external and bomb" {
  let info = dtd_test_parse(
    "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b '&a;'><!ENTITY ext SYSTEM 'urn:no-fetch'>]>",
  )
  for text in ["&a;", "&ext;", "&missing;"] {
    assert_true(
      try {
        ignore(dtd_normalize_attribute(info, text, false))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  let b = StringBuilder()
  for _ in 0..<32768 {
    b.write_char('x')
  }
  assert_true(
    try {
      ignore(dtd_normalize_attribute(info, b.to_string(), false))
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "DTD predefined declarations require correct escaping" {
  ignore(
    dtd_test_parse(
      "<!DOCTYPE r [<!ENTITY lt '&#38;#60;'><!ENTITY amp '&#38;#38;'><!ENTITY gt '&#62;'><!ENTITY apos '&#39;'><!ENTITY quot '&#34;'>]>",
    ),
  )
  for
    source in [
      "<!DOCTYPE r [<!ENTITY lt '<'>]>", "<!DOCTYPE r [<!ENTITY amp '&#38;'>]>",
      "<!DOCTYPE r [<!ENTITY gt 'wrong'>]>", "<!DOCTYPE r [<!ENTITY lt SYSTEM 'urn:no-fetch'>]>",
    ] {
    assert_true(
      try {
        ignore(dtd_test_parse(source))
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "DTD recursive depth and declaration bounds" {
  let many = StringBuilder()
  many.write_string("<!DOCTYPE r [")
  for _ in 0..<257 {
    many.write_string("<!ELEMENT r EMPTY>")
  }
  many.write_string("]>")
  assert_true(
    try {
      ignore(dtd_test_parse(many.to_string()))
      false
    } catch {
      Invalid(_) => true
    },
  )
  let nested = StringBuilder()
  nested.write_string("<!DOCTYPE r [<!ELEMENT r ")
  for _ in 0..<34 {
    nested.write_char('(')
  }
  nested.write_char('a')
  for _ in 0..<34 {
    nested.write_char(')')
  }
  nested.write_string(">]>")
  assert_true(
    try {
      ignore(dtd_test_parse(nested.to_string()))
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "DTD xml id declaration errors retain duplicate and unused declarations" {
  let info = dtd_test_parse(
    "<!DOCTYPE r [<!ATTLIST unused xml:id CDATA #IMPLIED><!ATTLIST unused xml:id NMTOKEN #IMPLIED><!ATTLIST r xml:id ID #IMPLIED>]>",
  )
  assert_eq(info.xml_id_declaration_errors.length(), 2)
  assert_eq(info.attributes.length(), 2)
  assert_eq(info.attributes[0].declared_type, "CDATA")
}

///|
test "DTD replacement generated CR does not collapse following LF" {
  let info = dtd_test_parse("<!DOCTYPE r [<!ENTITY pair '&#13;\n'>]>")
  assert_eq(dtd_normalize_attribute(info, "a&pair;b", false), "a  b")
}

///|
test "DTD attribute budget is shared across separate normalization calls" {
  let info = dtd_test_parse("<!DOCTYPE r>")
  let b = StringBuilder()
  for _ in 0..<32000 {
    b.write_char('x')
  }
  let raw = b.to_string()
  let mut rejected = false
  for _ in 0..<33 {
    if !rejected {
      ignore(dtd_normalize_attribute(info, raw, false)) catch {
        Invalid(_) => rejected = true
      }
    }
  }
  assert_true(rejected)
}
