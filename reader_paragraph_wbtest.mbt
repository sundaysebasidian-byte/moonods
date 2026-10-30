///|
fn paragraph_case(xml : String) -> String raise OdsError {
  let result = loss_case(
    "<t:table-cell o:value-type='string'>" + xml + "</t:table-cell>",
  )
  match result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value() {
    Text(s) => s
    _ => abort("expected text")
  }
}

///|
test "paragraph raw XML whitespace collapses across spans" {
  assert_eq(paragraph_case("<x:p>  a   b  </x:p>"), "a b")
  assert_eq(paragraph_case("<x:p> a <x:span>  b </x:span>  c </x:p>"), "a b c")
  assert_eq(paragraph_case("<x:p> a\n\tb&#xD;  c </x:p>"), "a b c")
  assert_eq(paragraph_case("<x:p> \t<x:span>\n</x:span> </x:p>"), "")
  assert_eq(paragraph_case("<x:p> </x:p>"), "")
  assert_eq(paragraph_case("<x:p><x:s/></x:p>"), " ")
  assert_eq(
    paragraph_case("<x:p>a<x:span> </x:span><x:span> </x:span>b</x:p>"),
    "a b",
  )
}

///|
test "paragraph explicit controls remain distinct from raw whitespace" {
  assert_eq(
    paragraph_case("<x:p><x:s x:c='2'/>a<x:tab/>b<x:line-break/>c<x:s/></x:p>"),
    "  a\tb\nc ",
  )
  assert_eq(
    paragraph_case(
      "<x:p>  <x:s/> a  <x:s/>  b <x:line-break/> c <x:tab/> </x:p>",
    ),
    "  a   b \n c \t",
  )
  assert_eq(paragraph_case("<x:p> a  b </x:p>"), "a  b")
  assert_eq(paragraph_case("<x:p>  a   </x:p>"), "  a  ")
}

///|
test "paragraph boundary resets collapse without discarding explicit spaces" {
  assert_eq(paragraph_case("<x:p> a </x:p><x:p> b </x:p>"), "a\nb")
  assert_eq(paragraph_case("<x:p><x:s/> </x:p><x:p> <x:s/></x:p>"), " \n ")
  assert_eq(paragraph_case("<x:p> </x:p><x:p/>"), "\n")
}

///|
test "paragraph own producer spaces and controls roundtrip" {
  for s in ["  a   b  ", " \t a\n  b \t", "   a  ", "  ", "\t\n"] {
    let w = Workbook::new()
    w.add_sheet("text").set(0, 0, Cell::new(Text(s)))
    let r = read_ods(w.to_ods(), allow_formatting_loss=true)
    assert_eq(
      r.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text(s),
    )
  }
}

///|
test "paragraph budget includes explicit controls and paragraph separators" {
  let max = Array::make(32767, "x").join("")
  assert_eq(paragraph_case("<x:p>" + max + "</x:p>"), max)
  assert_true(
    try {
      paragraph_case("<x:p>" + max + "<x:s/></x:p>") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      paragraph_case("<x:p>" + max + "</x:p><x:p/>") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_eq(paragraph_case("<x:p>" + max + "<x:span>    </x:span></x:p>"), max)
}

///|
test "paragraph carriage return uses authoritative typed attribute without display" {
  for s in ["a\rb", "a\r\nb", "\r", "  a\r\n b  "] {
    let w = Workbook::new()
    w.add_sheet("CR").set(0, 0, Cell::new(Text(s)))
    assert_true(w.content_xml().contains("office:string-value="))
    assert_false(w.content_xml().contains("<text:p>"))
    let r = read_ods(w.to_ods(), allow_formatting_loss=true).workbook()
    assert_eq(r.sheet(0).unwrap().get(0, 0).unwrap().value(), Text(s))
  }
}
