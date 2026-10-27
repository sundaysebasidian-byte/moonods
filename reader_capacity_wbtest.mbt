///|
test "capacity writer reads back a 100 by 100 numeric sheet" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Dense")
  for row in 0..<100 {
    for col in 0..<100 {
      sheet.set(row, col, Cell::new(Number((row * 100 + col).to_double())))
    }
  }
  let bytes = book.to_ods()
  let imported = read_ods(bytes, allow_formatting_loss=true)
  assert_eq(imported.workbook().sheet(0).unwrap().dimensions(), (100, 100))
  assert_eq(
    imported.workbook().sheet(0).unwrap().get(99, 99).unwrap().value(),
    Number(9999.0),
  )
}

///|
test "capacity repeated spaces roundtrip without XML node explosion" {
  let b = StringBuilder()
  for _ in 0..<32767 {
    b.write_char(' ')
  }
  let text = b.to_string()
  let book = Workbook::new()
  let sheet = book.add_sheet("Spaces")
  sheet.set_row(0, 0, [Cell::new(Text(text)), Cell::new(Text(text))])
  let imported = read_ods(book.to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(imported.get(0, 0).unwrap().value(), Text(text))
  assert_eq(imported.get(0, 1).unwrap().value(), Text(text))
}

///|
test "capacity 1024 repeated text rows fit writer and reader profile" {
  let text = Array::make(2000, "a").join("")
  let book = Workbook::new()
  let sheet = book.add_sheet("Repeated")
  for row in 0..<1024 {
    sheet.set(row, 0, Cell::new(Text(text)))
  }
  let saved = book.to_ods()
  let again = read_ods(saved, allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(again.dimensions(), (1024, 1))
  assert_eq(again.get(1023, 0).unwrap().value(), Text(text))
}

///|
test "capacity coalesced diagnostics retain exact count and locations" {
  for count in [31, 32, 33, 8192, 10000] {
    let notices = ReadNotices::new()
    for index in 0..<count {
      read_notice(notices, {
        sheet: "S",
        row: index / 100,
        col: index % 100,
        code: "FORMATTING_DROPPED",
        message: "style lost",
      })
    }
    assert_eq(
      notices.items.filter(d => d.code == "FORMATTING_DROPPED").length(),
      if count < 32 {
        count
      } else {
        32
      },
    )
    let summaries = notices.items.filter(d => {
      d.code == "FORMATTING_DROPPED_SUMMARY"
    })
    assert_eq(summaries.length(), if count > 32 { 1 } else { 0 })
    if count > 32 {
      assert_true(
        summaries[0].message.contains("\{count - 32} additional occurrences"),
      )
      assert_true(
        summaries[0].message.contains("first additional row 0 col 32"),
      )
      assert_true(
        summaries[0].message.contains(
          "last row \{(count - 1) / 100} col \{(count - 1) % 100}",
        ),
      )
    }
  }
}

///|
test "capacity grouped losses remain distinct by sheet and kind" {
  let notices = ReadNotices::new()
  for sheet in ["A", "B"] {
    for
      code in [
        "FORMATTING_DROPPED", "RICH_TEXT_FORMATTING_DROPPED", "NUMBER_PRECISION_CHANGED",
        "FORMULA_CACHE_NOT_RECALCULATED",
      ] {
      for i in 0..<100 {
        read_notice(notices, { sheet, row: i, col: 0, code, message: "loss", })
      }
    }
  }
  assert_eq(notices.items.length(), 8 * 33)
  assert_eq(
    notices.items.filter(d => d.code.has_suffix("_SUMMARY")).length(),
    8,
  )
}

///|
test "capacity sparse maximum grid has compact readable cell runs" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Sparse")
  sheet.set(1023, 63, Cell::new(Number(9.0)))
  let bytes = book.to_ods()
  let again = read_ods(bytes, allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(again.dimensions(), (1024, 64))
  assert_eq(again.get(1023, 63).unwrap().value(), Number(9.0))
}

///|
test "capacity mixed repeated cells preserve styles formula and merge boundaries" {
  let book = Workbook::new()
  let sheet = book.add_sheet("Runs")
  sheet.set_row(0, 0, [
    Cell::new(Text("  a  \t\n  b ")),
    Cell::new(Text("  a  \t\n  b ")),
    Cell::new(Text("x")).styled(Header),
  ])
  sheet.set_row(1, 0, [
    Cell::formula("of:=1", Number(1.0)),
    Cell::formula("of:=1", Number(1.0)),
  ])
  sheet.set(2, 0, Cell::new(Text("merged")))
  sheet.merge(2, 0, 1, 3)
  let again = read_ods(book.to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(again.get(0, 0).unwrap().value(), Text("  a  \t\n  b "))
  assert_eq(again.get(0, 1).unwrap().value(), again.get(0, 0).unwrap().value())
  assert_eq(again.get(0, 2).unwrap().value(), Text("x"))
  assert_eq(again.get(1, 1).unwrap().expression(), Some("of:=1"))
  assert_eq(again.merge_span(2, 0), Some((1, 3)))
  assert_true(again.is_covered(2, 2))
}

///|
test "capacity writer refuses unreadable byte profile without mutating book" {
  let text = Array::make(1500, "汉").join("")
  let book = Workbook::new()
  let sheet = book.add_sheet("Bytes")
  for r in 0..<1024 {
    sheet.set(r, 0, Cell::new(Text(text + r.to_string())))
  }
  let before = book.content_xml()
  let error = try {
    book.to_ods() |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("4 MiB reader profile"))
  assert_eq(book.content_xml(), before)
}

///|
test "capacity writer refuses unreadable control node profile" {
  let text = Array::make(32767, "\t").join("")
  let book = Workbook::new()
  book
  .add_sheet("Nodes")
  .set_row(0, 0, [
    Cell::new(Text(text)),
    Cell::new(Text(Array::make(32766, "\t").join("") + "\n")),
  ])
  let error = try {
    book.to_ods() |> ignore
    ""
  } catch {
    Invalid(msg) => msg
  }
  assert_true(error.contains("XML depth/node budget exceeded"))
}
