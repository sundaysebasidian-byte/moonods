///|
fn audit30_reject(action : () -> Unit raise OdsError) -> Bool {
  try {
    action()
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "audit30 R11 signed coordinate extrema reject before arithmetic mutation" {
  let b = Workbook::new()
  let s = b.add_sheet("Coordinates")
  s.set(0, 0, Cell::new(Number(1.0)))
  let before = b.to_ods()
  for bad in [-2147483647 - 1, -1, 2147483647] {
    assert_true(audit30_reject(() => s.set(bad, 0, Cell::new(Empty))))
    assert_true(audit30_reject(() => s.set(0, bad, Cell::new(Empty))))
    assert_true(audit30_reject(() => s.set_row(0, bad, [])))
    assert_true(audit30_reject(() => s.set_column_width(bad, 1)))
    assert_true(audit30_reject(() => s.set_row_height_length(bad, "1mm")))
    assert_true(audit30_reject(() => s.merge(0, 0, bad, 2)))
    assert_true(audit30_reject(() => s.merge(0, 0, 2, bad)))
    assert_eq(b.to_ods(), before)
    assert_true(s.get(bad, bad) is None)
  }
  assert_true(
    audit30_reject(() => s.set_row(0, 127, [Cell::new(Empty), Cell::new(Empty)])),
  )
  assert_true(audit30_reject(() => s.merge(1023, 127, 2, 2)))
  assert_eq(b.to_ods(), before)
}

///|
test "audit30 R12 sparse explicit and styled empties retain grid and semantics" {
  let b = Workbook::new()
  let s = b.add_sheet("Sparse")
  s.set(2, 2, Cell::new(Empty).styled(Highlight))
  s.set(2, 3, Cell::new(Text("")))
  s.set_column_width_length(5, "2.5mm")
  s.set_row_height_length(4, "12pt")
  assert_true(s.get(0, 0) is None)
  assert_eq(s.dimensions(), (5, 6))
  let out = read_ods(
      b.to_ods(),
      allow_formatting_loss=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(out.dimensions(), (5, 6))
  assert_eq(out.get(0, 0).unwrap().value(), Empty)
  assert_eq(out.get(2, 2).unwrap().value(), Empty)
  assert_eq(out.get(2, 2).unwrap().style(), Highlight)
  assert_eq(out.get(2, 3).unwrap().value(), Text(""))
  assert_eq(out.column_width_length(5), Some("2.5mm"))
  assert_eq(out.row_height_length(4), Some("12pt"))
  assert_eq(out.to_csv().split("\r\n").to_array().length(), 6)
}

///|
test "audit30 R13 every typed formula cache survives independent style and CSV policy" {
  let values = [
    Text("a,\"b"),
    Number(-2.5),
    Boolean(false),
    Date(1900, 3, 1),
    Percentage(0.125),
    Currency(12.5, "USD"),
    Duration("-PT0S"),
    DateTime("2026-10-31T01:02:03+14:00"),
  ]
  let expected = [
    "a,\"b", "-2.5", "false", "1900-03-01", "percentage:0.125", "currency:USD:12.5",
    "duration:-PT0S", "datetime:2026-10-31T01:02:03+14:00",
  ]
  let b = Workbook::new()
  let s = b.add_sheet("Caches")
  for i, value in values {
    s.set(0, i, Cell::formula("of:=1", value).styled(Highlight))
  }
  let out = read_ods(
      b.to_ods(),
      allow_formatting_loss=true,
      allow_extended_types=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  for i, value in values {
    assert_eq(out.get(0, i).unwrap().value(), value)
    assert_eq(out.get(0, i).unwrap().expression(), Some("of:=1"))
    assert_eq(out.get(0, i).unwrap().style(), Highlight)
  }
  assert_true(
    audit30_reject(() => out.to_csv(extended_types_as_text=true) |> ignore),
  )
  assert_true(
    audit30_reject(() => out.to_csv(use_formula_cache=true) |> ignore),
  )
  let csv = out.to_csv(use_formula_cache=true, extended_types_as_text=true)
  let text = Workbook::new().add_csv_sheet("CSV", csv)
  for i, value in expected {
    assert_eq(text.get(0, i).unwrap().value(), Text(value))
  }
}

///|
test "audit30 R14 adjacent equal values do not collapse distinct styles or formula identity" {
  let b = Workbook::new()
  let s = b.add_sheet("Distinct")
  for i, style in [Plain, Header, Highlight, Decimal2, DateISO] {
    s.set(0, i, Cell::new(Number(7.0)).styled(style))
    s.set(1, i, Cell::new(Text("same")).styled(style))
  }
  s.set(0, 5, Cell::formula("of:=3+4", Number(7.0)))
  s.set(0, 6, Cell::formula("of:=2+5", Number(7.0)))
  let out = read_ods(
      b.to_ods(),
      allow_formatting_loss=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  for i, style in [Plain, Header, Highlight, Decimal2, DateISO] {
    assert_eq(out.get(0, i).unwrap().value(), Number(7.0))
    assert_eq(out.get(1, i).unwrap().value(), Text("same"))
    // Some numeric/date presentation presets are intentionally type-specific.
    if i < 3 {
      assert_eq(out.get(0, i).unwrap().style(), style)
      assert_eq(out.get(1, i).unwrap().style(), style)
    }
  }
  assert_eq(out.get(0, 5).unwrap().expression(), Some("of:=3+4"))
  assert_eq(out.get(0, 6).unwrap().expression(), Some("of:=2+5"))
  assert_eq(out.dimensions(), (2, 7))
}

///|
test "audit30 R15 nonzero header mapping preserves row indices and exact Unicode keys" {
  let b = Workbook::new()
  let s = b.add_sheet("LateHeader")
  s.set_row(2, 0, [
    Cell::new(Text("é")),
    Cell::new(Text("é")),
    Cell::new(Text("\u00a0K\u00a0")),
  ])
  s.set_row(4, 0, [
    Cell::new(Boolean(true)),
    Cell::new(Number(2.0)),
    Cell::new(Text("")),
  ])
  let rows = s.records(header_row=2)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].row, 3)
  assert_eq(rows[0].values["é"], Empty)
  assert_eq(rows[1].row, 4)
  assert_eq(rows[1].values["é"], Number(2.0))
  assert_eq(rows[1].values["\u00a0K\u00a0"], Text(""))
  for h in [-1, 0, 1, 5, 2147483647] {
    assert_true(audit30_reject(() => s.records(header_row=h) |> ignore))
  }
  s.set(2, 0, Cell::new(Text("\u00a0")))
  assert_eq(s.records(header_row=2)[0].values["\u00a0"], Empty)
  s.set(2, 0, Cell::new(Text(" \t\r\n")))
  assert_true(audit30_reject(() => s.records(header_row=2) |> ignore))
}

///|
test "audit30 R16 quote expansion distinguishes CSV input and decoded text budgets" {
  let quoted = "\"" + Array::make(32767, "\"\"").join("") + "\""
  let b = Workbook::new()
  let s = b.add_csv_sheet("Fits", Array::make(63, quoted).join(","))
  assert_eq(s.dimensions(), (1, 63))
  assert_eq(
    s.get(0, 62).unwrap().value(),
    Text(Array::make(32767, "\"").join("")),
  )
  assert_true(
    audit30_reject(() => {
      b.add_csv_sheet("EncodedOver", Array::make(64, quoted).join(","))
      |> ignore
    }),
  )
  assert_eq(b.sheet_count(), 1)
  let bom = Workbook::new().add_csv_sheet("BOM", "\uFEFFheader\nvalue")
  assert_eq(bom.get(0, 0).unwrap().value(), Text("\uFEFFheader"))
  assert_eq(bom.to_csv(), "\"\uFEFFheader\"\r\n\"value\"\r\n")
}

///|
test "audit30 R17 ASCII folding and nonASCII sheet identity remain portable" {
  for pair in [("ΣA", "Σa"), ("KB", "Kb"), ("ẞC", "ẞc")] {
    let b = Workbook::new()
    b.add_sheet(pair.0) |> ignore
    assert_true(audit30_reject(() => b.add_sheet(pair.1) |> ignore))
    assert_eq(b.sheet_count(), 1)
  }
  let b = Workbook::new()
  for name in ["é", "é", "ß", "ss", "Σ", "σ", "ς", "K", "k", "ẞ"] {
    b.add_sheet(name) |> ignore
  }
  assert_eq(b.sheet_count(), 10)
  let out = read_ods(b.to_ods(), allow_formatting_loss=true).workbook()
  for i, name in ["é", "é", "ß", "ss", "Σ", "σ", "ς", "K", "k", "ẞ"] {
    assert_eq(out.sheet(i).unwrap().name(), name)
  }
}

///|
test "audit30 R18 repeated XML import counts real loss occurrences by sheet and code" {
  let cell = "<t:table-cell xmlns:f=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" t:formula=\"f:=1\" o:value-type=\"float\" o:value=\"9007199254740993\"/>"
  let table = (name, count) => {
    "<t:table t:name=\"\{name}\"><t:table-row t:number-rows-repeated=\"\{count}\">\{cell}</t:table-row></t:table>"
  }
  let xml = reader_xml_fixture("").replace(
    old="<t:table t:name=\"Input\"></t:table>",
    new=table("First", 40) + table("Second", 70),
  )
  let imported = import_content(xml)
  for pair in [("First", 8), ("Second", 38)] {
    for code in ["NUMBER_PRECISION_CHANGED", "FORMULA_CACHE_NOT_RECALCULATED"] {
      let exact = imported
        .diagnostics()
        .filter(d => d.sheet == pair.0 && d.code == code)
      assert_eq(exact.length(), 32)
      for i, d in exact {
        assert_eq((d.row, d.col), (i, 0))
      }
      let summary = imported
        .diagnostics()
        .filter(d => d.sheet == pair.0 && d.code == code + "_SUMMARY")
      assert_eq(summary.length(), 1)
      assert_true(
        summary[0].message.contains("\{pair.1} additional occurrences"),
      )
      assert_true(summary[0].message.contains("first additional row 32 col 0"))
      assert_true(summary[0].message.contains("last row \{pair.1 + 31} col 0"))
    }
  }
  let before = imported.diagnostics()
  imported.workbook().sheet(0).unwrap().set(0, 0, Cell::new(Number(1.0)))
  assert_eq(imported.diagnostics(), before)
}
