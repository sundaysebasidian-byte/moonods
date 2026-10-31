///|
test "repeated rows preserve independent horizontal merge anchors and values" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row t:number-rows-repeated='3'><t:table-cell o:value-type='string' o:string-value='value' t:number-columns-spanned='2'/><t:covered-table-cell/><t:table-cell o:value-type='float' o:value='7'/></t:table-row>",
    ),
  )
  let sheet = result.workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions().0, 3)
  for r in 0..<3 {
    assert_eq(sheet.merge_span(r, 0), Some((1, 2)))
    assert_true(sheet.is_covered(r, 1))
    assert_eq(sheet.get(r, 0).unwrap().value(), Text("value"))
    assert_eq(sheet.get(r, 2).unwrap().value(), Number(7))
  }
}

///|
test "repeated horizontal merges retain boundaries around other rows" {
  let result = import_content(
    reader_xml_fixture(
      "<t:table-row><t:table-cell o:value-type='float' o:value='1'/></t:table-row><t:table-row t:number-rows-repeated='2'><t:table-cell/><t:table-cell o:value-type='string' o:string-value='merged' t:number-columns-spanned='2'/><t:covered-table-cell/></t:table-row><t:table-row><t:table-cell o:value-type='float' o:value='9'/></t:table-row>",
    ),
  )
  let sheet = result.workbook().sheet(0).unwrap()
  assert_eq(sheet.dimensions().0, 4)
  assert_eq(sheet.get(0, 0).unwrap().value(), Number(1))
  assert_eq(sheet.get(3, 0).unwrap().value(), Number(9))
  assert_eq(sheet.merge_span(1, 1), Some((1, 2)))
  assert_eq(sheet.merge_span(2, 1), Some((1, 2)))
  assert_eq(sheet.merge_span(3, 1), None)
}

///|
test "row repeated horizontal merges do not weaken covered geometry or repetition constraints" {
  for
    body in [
      "<t:table-row t:number-rows-repeated='2'><t:table-cell t:number-columns-spanned='2'/></t:table-row>",
      "<t:table-row t:number-rows-repeated='2'><t:table-cell t:number-columns-spanned='2'/><t:table-cell/></t:table-row>",
      "<t:table-row t:number-rows-repeated='2'><t:table-cell t:number-rows-spanned='2'/></t:table-row>",
      "<t:table-row><t:table-cell t:number-columns-repeated='2' t:number-rows-spanned='2'/></t:table-row><t:table-row><t:covered-table-cell t:number-columns-repeated='2'/></t:table-row>",
      "<t:table-row><t:table-cell t:number-columns-repeated='2' t:number-columns-spanned='2'/><t:covered-table-cell/></t:table-row>",
    ] {
    assert_true(
      try {
        import_content(reader_xml_fixture(body)) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}
