///|
test "CDATA is literal content with XML line ending normalization" {
  let root = read_xml("<root>a<![CDATA[<&amp;\r\nb]]>c<![CDATA[]]></root>")
  let mut text = ""
  for part in root.parts {
    if part is ReadText(value) {
      text += value
    }
  }
  assert_eq(text, "a<&amp;\nbc")
}

///|
test "CDATA malformed placement termination controls and budgets reject" {
  for
    xml in [
      "<![CDATA[text]]><root/>", "<root a=\"<![CDATA[x]]>\"/>", "<root><![CDATA[x</root>",
      "<root><![CDATA[\u0001]]></root>",
    ] {
    let rejected = try {
      ignore(read_xml(xml))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  let long = "x".repeat(32768)
  let rejected = try {
    ignore(read_xml("<root><![CDATA[\{long}]]></root>"))
    false
  } catch {
    Invalid(_) => true
  }
  assert_true(rejected)
}

///|
test "XML comments and PIs around and inside elements do not change text" {
  let root = read_xml(
    "<!--pre--><?before x?><root>a<!--mid--><?step value?>b</root><?after?><!--end-->",
  )
  let mut text = ""
  for part in root.parts {
    if part is ReadText(value) {
      text += value
    }
  }
  assert_eq(text, "ab")
}

///|
test "malformed XML comments and PIs are rejected" {
  for
    xml in [
      "<root><!--a--b--></root>", "<root><!--a</root>", "<root><?pi unfinished</root>",
      "<root><?XML x?></root>", "<root><?pi=value?></root>", "<!--\u0001--><root/>",
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
