///|
fn csv_rejected(text : String) -> Bool {
  let book = Workbook::new()
  let rejected = try {
    book.add_csv_sheet("Data", text) |> ignore
    false
  } catch {
    Invalid(_) => true
  }
  rejected && book.sheet_count() == 0
}

///|
test "CSV accepts column and UTF16 boundaries while enforcing total text" {
  let row = Array::make(128, "x").join(",")
  assert_eq(Workbook::new().add_csv_sheet("Wide", row).dimensions(), (1, 128))
  let unicode = Array::make(16383, "😀").join("")
  assert_eq(
    Workbook::new().add_csv_sheet("Unicode", unicode).get(0, 0).unwrap().value(),
    Text(unicode),
  )
  assert_true(csv_rejected(unicode + "😀"))
  let field = Array::make(32767, "x").join("")
  assert_true(csv_rejected(Array::make(65, field).join(",")))
}

///|
test "CSV quoting unicode empty cells and ODS reread" {
  let book = Workbook::new()
  let source = "Name,Note,Empty\r\n中文,\"comma,quote\"\"and\r\nline\",\r\n=1+2,  spaces  ,\"\""
  let sheet = book.add_csv_sheet("Data", source)
  assert_eq(sheet.dimensions(), (3, 3))
  assert_eq(sheet.get(1, 1).unwrap().value(), Text("comma,quote\"and\r\nline"))
  assert_eq(sheet.get(2, 0).unwrap().expression(), None)
  assert_eq(sheet.get(2, 0).unwrap().value(), Text("=1+2"))
  assert_eq(sheet.get(1, 2).unwrap().value(), Text(""))
  let again = read_ods(book.to_ods(), allow_formatting_loss=true).workbook()
  assert_eq(again.sheet(0).unwrap().to_csv(), sheet.to_csv())
  let imported = Workbook::new().add_csv_sheet("Again", sheet.to_csv())
  assert_eq(imported.to_csv(), sheet.to_csv())
  assert_eq(imported.records()[0].values["Name"], Text("中文"))
  for text in ["", "\"\"", "\n", "\r\n"] {
    assert_eq(Workbook::new().add_csv_sheet("Empty", text).dimensions(), (1, 1))
  }
  assert_eq(
    Workbook::new().add_csv_sheet("LF", "a,b\nc,d\n").dimensions(),
    (2, 2),
  )
}

///|
test "CSV rejects malformed input and limits before workbook mutation" {
  for text in ["\"a", "a\"b", "\"a\"x", "a\rb", "a\r", "a,b\nc", "\u0000"] {
    assert_true(csv_rejected(text))
  }
  assert_true(csv_rejected(Array::make(129, "x").join(",")))
  assert_true(csv_rejected(Array::make(1025, "x").join("\n")))
  assert_true(
    csv_rejected(Array::make(513, Array::make(128, "x").join(",")).join("\n")),
  )
  assert_true(csv_rejected(Array::make(32768, "x").join("")))
  let book = Workbook::new()
  let _ = book.add_csv_sheet("Data", "name\nfirst")
  assert_true(
    try {
      book.add_csv_sheet("data", "name\nsecond") |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(book.sheet_count(), 1)
  assert_eq(book.sheet(0).unwrap().get(1, 0).unwrap().value(), Text("first"))
}

///|
test "CSV typed export and explicit cached formula policy" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Types")
  sheet.set_row(0, 0, [
    Cell::new(Number(-0.0)),
    Cell::new(Boolean(true)),
    Cell::new(Date(2024, 2, 29)),
    Cell::new(Empty),
  ])
  assert_eq(sheet.to_csv(), "\"-0\",\"true\",\"2024-02-29\",\"\"\r\n")
  sheet.set(1, 0, Cell::formula("of:=1+2", Number(99.0)))
  assert_true(
    try {
      sheet.to_csv() |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(sheet.to_csv(use_formula_cache=true).contains("\"99\""))
  assert_eq(sheet.get(1, 0).unwrap().expression(), Some("of:=1+2"))
  sheet.merge(2, 0, 1, 2)
  assert_true(
    try {
      sheet.to_csv(use_formula_cache=true) |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "header records preserve types source rows blanks and snapshots across sheets" {
  let book = Workbook::new()
  let s = book.add_sheet("Data")
  s.set_row(1, 0, [
    Cell::new(Text("Name")),
    Cell::new(Text("value")),
    Cell::new(Text("Empty")),
  ])
  s.set_row(2, 0, [
    Cell::new(Text("first")),
    Cell::new(Number(7.5)),
    Cell::new(Text("")),
  ])
  s.set(4, 1, Cell::formula("of:=1+2", Boolean(true)))
  let records = s.records(header_row=1)
  assert_eq(records.length(), 3)
  assert_eq(records[0].row, 2)
  assert_eq(records[0].values["value"], Number(7.5))
  assert_eq(records[0].values["Empty"], Text(""))
  assert_eq(records[1].values["Empty"], Empty)
  assert_eq(records[2].values["value"], Boolean(true))
  records[0].values["value"] = Number(0.0)
  assert_eq(s.get(2, 1).unwrap().value(), Number(7.5))
  let other = book.add_csv_sheet("Other", "name\nsecond")
  assert_eq(other.records()[0].values["name"], Text("second"))
  assert_eq(book.sheet_count(), 2)
}

///|
test "records reject ambiguous headers and merged grids" {
  for
    headers in [
      [Text("x"), Text("x")],
      [Text("x"), Text(" ")],
      [Text("x"), Number(1.0)],
    ] {
    let sheet = Workbook::new().add_sheet("Bad")
    sheet.set_row(0, 0, headers.map(v => Cell::new(v)))
    assert_true(
      try {
        sheet.records() |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  let sheet = Workbook::new().add_csv_sheet("Data", "a,b\n1,2")
  for row in [-1, 2] {
    assert_true(
      try {
        sheet.records(header_row=row) |> ignore
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
  sheet.set(0, 0, Cell::formula("of:=\"a\"", Text("a")))
  assert_true(
    try {
      sheet.records() |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
  sheet.set(0, 0, Cell::new(Text("a")))
  sheet.merge(2, 0, 1, 2)
  assert_true(
    try {
      sheet.records() |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
}
