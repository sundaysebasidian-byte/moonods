///|
test "formula alias normalizes outer prefix and preserves cache on export reread" {
  let result = loss_case(
    "<t:table-cell xmlns:f='urn:oasis:names:tc:opendocument:xmlns:of:1.2' t:formula='f:=1+2' o:value-type='float' o:value='3'/>",
  )
  let cell = result.workbook().sheet(0).unwrap().get(0, 0).unwrap()
  assert_eq(cell.expression(), Some("of:=1+2"))
  assert_eq(cell.value(), Number(3.0))
  let again = read_ods(result.workbook().to_ods(), allow_formatting_loss=true)
  let round = again.workbook().sheet(0).unwrap().get(0, 0).unwrap()
  assert_eq(round.expression(), Some("of:=1+2"))
  assert_eq(round.value(), Number(3.0))
}

///|
test "formula prefix uses inherited and locally rebound namespace mappings" {
  let root = read_xml(
    "<a xmlns:f='urn:oasis:names:tc:opendocument:xmlns:of:1.2'><b/><c xmlns:f='urn:wrong'/></a>",
  )
  for part in root.parts {
    if part is ReadElement(child) {
      if child.name == "#b" {
        assert_eq(read_formula_prefix("f:=1", child.ns), "of:=1")
      } else {
        let rejected = try {
          ignore(read_formula_prefix("f:=1", child.ns))
          false
        } catch {
          Invalid(_) => true
        }
        assert_true(rejected)
      }
    }
  }
  let rebound = read_xml(
    "<a xmlns:f='urn:wrong'><b xmlns:f='urn:oasis:names:tc:opendocument:xmlns:of:1.2'/></a>",
  )
  for part in rebound.parts {
    if part is ReadElement(child) {
      assert_eq(read_formula_prefix("f:=1", child.ns), "of:=1")
    }
  }
}

///|
test "formula prefix rejects missing wrong bindings and malformed empty expressions" {
  let ns : Map[String, String] = {
    "f": "urn:oasis:names:tc:opendocument:xmlns:of:1.2",
    "wrong": "urn:wrong",
  }
  for f in ["x:=1", "wrong:=1", "f:=", "f:1", ":=1", "1f:=1", "f::=1", "f"] {
    let rejected = try {
      ignore(read_formula_prefix(f, ns))
      false
    } catch {
      Invalid(_) => true
    }
    assert_true(rejected)
  }
  assert_eq(
    read_formula_prefix("f:=CUSTOM(\"f:=\")", ns),
    "of:=CUSTOM(\"f:=\")",
  )
}
