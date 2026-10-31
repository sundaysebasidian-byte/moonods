///|
fn audit20_throws(f : () -> Unit raise OdsError) -> Bool {
  try {
    f()
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "audit20 R01 independent Python csv generator text semantics" {
  let cases : Array[(String, Array[Array[String]])] = [
    (
      "\"x\r\ny\",\"\n\",\" x\"\n\"a,b\",\"a\"\"b\",\"\"\n",
      [["x\r\ny", "\n", " x"], ["a,b", "a\"b", ""]],
    ),
    (
      "\"\n\",\"\n\",=SUM(A1)\r\n\"\n\",\"\"\"\",\"a,b\"\r\n",
      [["\n", "\n", "=SUM(A1)"], ["\n", "\"", "a,b"]],
    ),
    (
      " tail , tail ,\n\"x\r\ny\",\"\n\",\"a,b\"\n",
      [[" tail ", " tail ", ""], ["x\r\ny", "\n", "a,b"]],
    ),
    (
      "\"\n\",\" tail \",\"=SUM(A1)\"\r\n\"\"\"\",\" x\",\"汉🧪\"\r\n",
      [["\n", " tail ", "=SUM(A1)"], ["\"", " x", "汉🧪"]],
    ),
    (
      " tail ,\"\n\",\"a,b\"\n, x,\"\"\"\"\n",
      [[" tail ", "\n", "a,b"], ["", " x", "\""]],
    ),
    (
      " x,=SUM(A1),\"a\"\"b\"\r\n汉🧪,=SUM(A1),汉🧪\r\n",
      [[" x", "=SUM(A1)", "a\"b"], ["汉🧪", "=SUM(A1)", "汉🧪"]],
    ),
    (
      "\" x\",\"汉🧪\",\" x\"\n\"汉🧪\",\"a,b\",\"a\"\"b\"\n",
      [[" x", "汉🧪", " x"], ["汉🧪", "a,b", "a\"b"]],
    ),
    (
      "\"x\r\ny\",\"\"\"\",\r\n x,\"a,b\",\"x\r\ny\"\r\n",
      [["x\r\ny", "\"", ""], [" x", "a,b", "x\r\ny"]],
    ),
    (
      " x,\"a,b\", tail \n\"\n\",\"\n\",\"\"\"\"\n",
      [[" x", "a,b", " tail "], ["\n", "\n", "\""]],
    ),
    (
      "\"a,b\",\"a\"\"b\",\"\n\"\r\n\"a,b\",\"\"\"\",\"a\"\"b\"\r\n",
      [["a,b", "a\"b", "\n"], ["a,b", "\"", "a\"b"]],
    ),
    (
      "\"\n\",\"a,b\",\n\"\n\",汉🧪, x\n",
      [["\n", "a,b", ""], ["\n", "汉🧪", " x"]],
    ),
    (
      "\"a\"\"b\",\"a\"\"b\",\"\n\"\r\n\"a,b\",汉🧪, tail \r\n",
      [["a\"b", "a\"b", "\n"], ["a,b", "汉🧪", " tail "]],
    ),
    (
      "\"a\"\"b\",\"\n\",\"\n\"\n\"=SUM(A1)\",\"=SUM(A1)\",\"a\"\"b\"\n",
      [["a\"b", "\n", "\n"], ["=SUM(A1)", "=SUM(A1)", "a\"b"]],
    ),
    (
      "\"\"\"\",\"a\"\"b\", tail \r\n tail ,, x\r\n",
      [["\"", "a\"b", " tail "], [" tail ", "", " x"]],
    ),
    (
      "\"\"\"\",,\"x\r\ny\"\n,,\"a,b\"\n",
      [["\"", "", "x\r\ny"], ["", "", "a,b"]],
    ),
    (
      "\"\",\"a,b\",\"x\r\ny\"\r\n\"\n\",\"汉🧪\",\"\n\"\r\n",
      [["", "a,b", "x\r\ny"], ["\n", "汉🧪", "\n"]],
    ),
    (
      "\"a\"\"b\",汉🧪,\"x\r\ny\"\n\"\n\",\"x\r\ny\",\"\n\"\n",
      [["a\"b", "汉🧪", "x\r\ny"], ["\n", "x\r\ny", "\n"]],
    ),
    (
      "\"a\"\"b\",汉🧪, tail \r\n汉🧪,\"\"\"\",=SUM(A1)\r\n",
      [["a\"b", "汉🧪", " tail "], ["汉🧪", "\"", "=SUM(A1)"]],
    ),
    (
      "\"=SUM(A1)\",\"a\"\"b\",\"\"\n\"\",\"\",\"x\r\ny\"\n",
      [["=SUM(A1)", "a\"b", ""], ["", "", "x\r\ny"]],
    ),
    (
      "\"a\"\"b\",=SUM(A1),\"a\"\"b\"\r\n tail ,\"x\r\ny\",\"a,b\"\r\n",
      [["a\"b", "=SUM(A1)", "a\"b"], [" tail ", "x\r\ny", "a,b"]],
    ),
    (
      "\"\"\"\", tail ,\"\n\"\n\"a\"\"b\", tail ,\"x\r\ny\"\n",
      [["\"", " tail ", "\n"], ["a\"b", " tail ", "x\r\ny"]],
    ),
    (
      "\"a,b\",\"a\"\"b\",\"x\r\ny\"\r\n\" x\",\"x\r\ny\",\"=SUM(A1)\"\r\n",
      [["a,b", "a\"b", "x\r\ny"], [" x", "x\r\ny", "=SUM(A1)"]],
    ),
    (
      "\"\n\",\"a,b\", tail \n tail ,\"x\r\ny\", tail \n",
      [["\n", "a,b", " tail "], [" tail ", "x\r\ny", " tail "]],
    ),
    (
      "\"\n\", x,\"\"\"\"\r\n\"a,b\", tail ,汉🧪\r\n",
      [["\n", " x", "\""], ["a,b", " tail ", "汉🧪"]],
    ),
    (
      "\"=SUM(A1)\",\"a\"\"b\",\"x\r\ny\"\n\"a,b\",\"x\r\ny\",\" x\"\n",
      [["=SUM(A1)", "a\"b", "x\r\ny"], ["a,b", "x\r\ny", " x"]],
    ),
    (
      "汉🧪,\"\n\",汉🧪\r\n x,,\r\n",
      [["汉🧪", "\n", "汉🧪"], [" x", "", ""]],
    ),
    (
      "\"\n\",\"a\"\"b\",\"a,b\"\n\"\n\",汉🧪,\"\n\"\n",
      [["\n", "a\"b", "a,b"], ["\n", "汉🧪", "\n"]],
    ),
    (
      "\"a,b\",\"x\r\ny\",\" tail \"\r\n\"汉🧪\",\"\",\"汉🧪\"\r\n",
      [["a,b", "x\r\ny", " tail "], ["汉🧪", "", "汉🧪"]],
    ),
    (
      "\"a\"\"b\",汉🧪, tail \n\"\n\",\"x\r\ny\",\"a,b\"\n",
      [["a\"b", "汉🧪", " tail "], ["\n", "x\r\ny", "a,b"]],
    ),
    (
      "\"\"\"\",\"\"\"\",\r\n\"a\"\"b\",\"\n\",\"\n\"\r\n",
      [["\"", "\"", ""], ["a\"b", "\n", "\n"]],
    ),
    (
      "\" tail \",\"\",\" x\"\n\"a\"\"b\",\"\",\"x\r\ny\"\n",
      [[" tail ", "", " x"], ["a\"b", "", "x\r\ny"]],
    ),
    (
      "\"x\r\ny\",\"\n\",\"a\"\"b\"\r\n\"\n\",\"\n\",\"a\"\"b\"\r\n",
      [["x\r\ny", "\n", "a\"b"], ["\n", "\n", "a\"b"]],
    ),
    (
      " tail ,\"x\r\ny\",汉🧪\n\"x\r\ny\",=SUM(A1), x\n",
      [[" tail ", "x\r\ny", "汉🧪"], ["x\r\ny", "=SUM(A1)", " x"]],
    ),
    (
      "\"a\"\"b\",\"\n\",\"x\r\ny\"\r\n\"=SUM(A1)\",\"x\r\ny\",\"\n\"\r\n",
      [["a\"b", "\n", "x\r\ny"], ["=SUM(A1)", "x\r\ny", "\n"]],
    ),
    (
      " x, x,\"a\"\"b\"\n\"x\r\ny\",\"a\"\"b\",\"\"\"\"\n",
      [[" x", " x", "a\"b"], ["x\r\ny", "a\"b", "\""]],
    ),
    (
      "\"x\r\ny\",=SUM(A1), tail \r\n\"\n\",\"\n\",汉🧪\r\n",
      [["x\r\ny", "=SUM(A1)", " tail "], ["\n", "\n", "汉🧪"]],
    ),
    (
      "\"x\r\ny\",\"=SUM(A1)\",\"x\r\ny\"\n\"a,b\",\"=SUM(A1)\",\" tail \"\n",
      [["x\r\ny", "=SUM(A1)", "x\r\ny"], ["a,b", "=SUM(A1)", " tail "]],
    ),
    (
      "\"x\r\ny\",\"\n\", x\r\n,,\"\"\"\"\r\n",
      [["x\r\ny", "\n", " x"], ["", "", "\""]],
    ),
    (
      " tail ,\"\"\"\",汉🧪\n\"\n\",\"a\"\"b\",\n",
      [[" tail ", "\"", "汉🧪"], ["\n", "a\"b", ""]],
    ),
    (
      "\"\"\"\",\"=SUM(A1)\",\" x\"\r\n\"x\r\ny\",\"汉🧪\",\"汉🧪\"\r\n",
      [["\"", "=SUM(A1)", " x"], ["x\r\ny", "汉🧪", "汉🧪"]],
    ),
    (
      "汉🧪,汉🧪,汉🧪\n tail ,汉🧪,\"a,b\"\n",
      [["汉🧪", "汉🧪", "汉🧪"], [" tail ", "汉🧪", "a,b"]],
    ),
    (
      "汉🧪,\"\"\"\", x\r\n, tail ,\"x\r\ny\"\r\n",
      [["汉🧪", "\"", " x"], ["", " tail ", "x\r\ny"]],
    ),
    (
      "\"=SUM(A1)\",\"\",\"\"\n\"a\"\"b\",\"\",\" tail \"\n",
      [["=SUM(A1)", "", ""], ["a\"b", "", " tail "]],
    ),
    (
      ",\"\n\",\"\"\"\"\r\n x, tail ,\r\n",
      [["", "\n", "\""], [" x", " tail ", ""]],
    ),
    (
      " tail ,\"a\"\"b\",\"x\r\ny\"\n tail ,\"\n\",\"x\r\ny\"\n",
      [[" tail ", "a\"b", "x\r\ny"], [" tail ", "\n", "x\r\ny"]],
    ),
    (
      "\" tail \",\"汉🧪\",\"\"\r\n\"\",\"x\r\ny\",\"\"\"\"\r\n",
      [[" tail ", "汉🧪", ""], ["", "x\r\ny", "\""]],
    ),
    (
      ",=SUM(A1),汉🧪\n\"a\"\"b\",\"\n\",\"\"\"\"\n",
      [["", "=SUM(A1)", "汉🧪"], ["a\"b", "\n", "\""]],
    ),
    (
      "汉🧪,\"a\"\"b\", tail \r\n\"a\"\"b\",\"a,b\",\"\"\"\"\r\n",
      [["汉🧪", "a\"b", " tail "], ["a\"b", "a,b", "\""]],
    ),
    (
      "\"x\r\ny\",\"a,b\",\" tail \"\n\"汉🧪\",\"x\r\ny\",\"a,b\"\n",
      [["x\r\ny", "a,b", " tail "], ["汉🧪", "x\r\ny", "a,b"]],
    ),
    (
      " tail ,\"x\r\ny\",=SUM(A1)\r\n tail ,=SUM(A1),\"a,b\"\r\n",
      [[" tail ", "x\r\ny", "=SUM(A1)"], [" tail ", "=SUM(A1)", "a,b"]],
    ),
    (
      "=SUM(A1), tail ,\n tail ,\"x\r\ny\",\"\n\"\n",
      [["=SUM(A1)", " tail ", ""], [" tail ", "x\r\ny", "\n"]],
    ),
    (
      "\" tail \",\" x\",\"\n\"\r\n\"x\r\ny\",\" x\",\"汉🧪\"\r\n",
      [[" tail ", " x", "\n"], ["x\r\ny", " x", "汉🧪"]],
    ),
    (
      "\"\"\"\", tail , tail \n汉🧪,\"\n\",\"\"\"\"\n",
      [["\"", " tail ", " tail "], ["汉🧪", "\n", "\""]],
    ),
    (
      "\"a,b\",,汉🧪\r\n\"x\r\ny\",\"a\"\"b\",\r\n",
      [["a,b", "", "汉🧪"], ["x\r\ny", "a\"b", ""]],
    ),
    (
      "\"a\"\"b\",\"x\r\ny\",\"汉🧪\"\n\" tail \",\"a,b\",\" x\"\n",
      [["a\"b", "x\r\ny", "汉🧪"], [" tail ", "a,b", " x"]],
    ),
    (
      " x,\"x\r\ny\",\"\"\"\"\r\n x,\"\"\"\",\"a,b\"\r\n",
      [[" x", "x\r\ny", "\""], [" x", "\"", "a,b"]],
    ),
    (
      " x, x,\n,=SUM(A1),\"x\r\ny\"\n",
      [[" x", " x", ""], ["", "=SUM(A1)", "x\r\ny"]],
    ),
    (
      "\"a,b\",\"汉🧪\",\"汉🧪\"\r\n\"\",\"\n\",\"\"\r\n",
      [["a,b", "汉🧪", "汉🧪"], ["", "\n", ""]],
    ),
    (
      "\"\n\",,\n\"\n\", tail ,\"\"\"\"\n",
      [["\n", "", ""], ["\n", " tail ", "\""]],
    ),
    (
      "\"\"\"\",\"\"\"\", x\r\n\"a,b\",\"\"\"\",=SUM(A1)\r\n",
      [["\"", "\"", " x"], ["a,b", "\"", "=SUM(A1)"]],
    ),
    (
      "\"=SUM(A1)\",\" tail \",\"x\r\ny\"\n\"\",\"a,b\",\" tail \"\n",
      [["=SUM(A1)", " tail ", "x\r\ny"], ["", "a,b", " tail "]],
    ),
    (
      " tail ,,\"a\"\"b\"\r\n\"\"\"\",,\"a\"\"b\"\r\n",
      [[" tail ", "", "a\"b"], ["\"", "", "a\"b"]],
    ),
    (
      " tail ,,\"x\r\ny\"\n x, tail ,汉🧪\n",
      [[" tail ", "", "x\r\ny"], [" x", " tail ", "汉🧪"]],
    ),
    (
      "\"x\r\ny\",\"=SUM(A1)\",\" x\"\r\n\"\",\" tail \",\"a,b\"\r\n",
      [["x\r\ny", "=SUM(A1)", " x"], ["", " tail ", "a,b"]],
    ),
    (
      "\"\n\",\"\"\"\",\"\n\"\n汉🧪,=SUM(A1),\"\"\"\"\n",
      [["\n", "\"", "\n"], ["汉🧪", "=SUM(A1)", "\""]],
    ),
    (
      "\"a\"\"b\",=SUM(A1),\r\n\"a\"\"b\",,汉🧪\r\n",
      [["a\"b", "=SUM(A1)", ""], ["a\"b", "", "汉🧪"]],
    ),
    (
      "\"\n\",\"\",\"=SUM(A1)\"\n\"x\r\ny\",\"x\r\ny\",\"a,b\"\n",
      [["\n", "", "=SUM(A1)"], ["x\r\ny", "x\r\ny", "a,b"]],
    ),
    (
      "\"\"\"\",\"\n\",\"a,b\"\r\n\"x\r\ny\",\"\"\"\",\"\n\"\r\n",
      [["\"", "\n", "a,b"], ["x\r\ny", "\"", "\n"]],
    ),
    (
      " tail ,,\"a\"\"b\"\n=SUM(A1),,\"a\"\"b\"\n",
      [[" tail ", "", "a\"b"], ["=SUM(A1)", "", "a\"b"]],
    ),
    (
      "\"=SUM(A1)\",\"\n\",\"\"\"\"\r\n\"汉🧪\",\"\"\"\",\"\"\"\"\r\n",
      [["=SUM(A1)", "\n", "\""], ["汉🧪", "\"", "\""]],
    ),
    (
      ",,\"a,b\"\n汉🧪,\"\n\",=SUM(A1)\n",
      [["", "", "a,b"], ["汉🧪", "\n", "=SUM(A1)"]],
    ),
    (
      "\"a,b\",=SUM(A1), x\r\n x,汉🧪, x\r\n",
      [["a,b", "=SUM(A1)", " x"], [" x", "汉🧪", " x"]],
    ),
    (
      "\"x\r\ny\",\" x\",\"a,b\"\n\" tail \",\"a\"\"b\",\"\"\n",
      [["x\r\ny", " x", "a,b"], [" tail ", "a\"b", ""]],
    ),
    (
      "\"a\"\"b\", tail ,\r\n=SUM(A1),\"x\r\ny\",\"x\r\ny\"\r\n",
      [["a\"b", " tail ", ""], ["=SUM(A1)", "x\r\ny", "x\r\ny"]],
    ),
    (
      " x, tail ,=SUM(A1)\n=SUM(A1),\"x\r\ny\",\"\"\"\"\n",
      [[" x", " tail ", "=SUM(A1)"], ["=SUM(A1)", "x\r\ny", "\""]],
    ),
    (
      "\"\n\",\" x\",\"=SUM(A1)\"\r\n\"\n\",\"x\r\ny\",\"a,b\"\r\n",
      [["\n", " x", "=SUM(A1)"], ["\n", "x\r\ny", "a,b"]],
    ),
    (
      " tail , x,\"\n\"\n tail ,\"a\"\"b\",\"\n\"\n",
      [[" tail ", " x", "\n"], [" tail ", "a\"b", "\n"]],
    ),
    (
      "\"x\r\ny\", tail , tail \r\n\"\n\",汉🧪,\"a,b\"\r\n",
      [["x\r\ny", " tail ", " tail "], ["\n", "汉🧪", "a,b"]],
    ),
    (
      "\"a,b\",\"a,b\",\"a\"\"b\"\n\"a\"\"b\",\"\",\"x\r\ny\"\n",
      [["a,b", "a,b", "a\"b"], ["a\"b", "", "x\r\ny"]],
    ),
    (
      "\"a,b\",\"a,b\",\"\"\"\"\r\n x,=SUM(A1),=SUM(A1)\r\n",
      [["a,b", "a,b", "\""], [" x", "=SUM(A1)", "=SUM(A1)"]],
    ),
  ]
  for (encoded, expected) in cases {
    let b = Workbook::new()
    let s = b.add_csv_sheet("Generated", encoded)
    assert_eq(s.dimensions(), (2, 3))
    for r, row in expected {
      for c, text in row {
        assert_eq(s.get(r, c).unwrap().value(), Text(text))
        assert_eq(s.get(r, c).unwrap().expression(), None)
      }
    }
    let s2 = Workbook::new().add_csv_sheet("Canonical", s.to_csv())
    for r, row in expected {
      for c, text in row {
        assert_eq(s2.get(r, c).unwrap().value(), Text(text))
      }
    }
  }
}

///|
test "audit20 R02 CSV late failure preserves existing multi sheet book" {
  let b = Workbook::new()
  b.add_csv_sheet("One", "A,B\n1,2") |> ignore
  b.add_csv_sheet("Two", "C,D\n3,4") |> ignore
  let before = b.to_ods()
  for
    bad in [
      "a,b\n\"\" ,x", "a,b\n\"x\"\t,y", "a,b\n\"x\"z,y", "a,b\n1,2\n3,\"q\"\"", "a,b\r\n1,2\r3,4",
      "a,b\n1,2\n3,4,5", "a,b\n1,2\n3,\u0001",
    ] {
    assert_true(audit20_throws(() => b.add_csv_sheet("New", bad) |> ignore))
    assert_eq(b.to_ods(), before)
  }
  let literal = b.add_csv_sheet("Literal", "v\n\u00a0=1")
  assert_eq(
    literal.to_csv(reject_formula_like_text=true),
    "\"v\"\r\n\"\u00a0=1\"\r\n",
  )
}

///|
test "audit20 R03 records schema snapshots and map isolation" {
  let b = Workbook::new()
  let s = b.add_sheet("Records")
  s.set_row(0, 0, [
    Cell::new(Text("Key")),
    Cell::new(Text("key")),
    Cell::new(Text(" key ")),
  ])
  s.set(2, 0, Cell::formula("of:=1", Number(1.0)))
  s.set(2, 1, Cell::new(Text("")))
  let rows = s.records()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].row, 1)
  assert_eq(rows[0].values["Key"], Empty)
  assert_eq(rows[1].values["key"], Text(""))
  rows[0].values["Key"] = Text("outside mutation")
  rows[1].values["key"] = Text("changed")
  rows.clear()
  assert_eq(s.records()[0].values["Key"], Empty)
  assert_eq(s.records()[1].values["key"], Text(""))
  s.set(0, 1, Cell::new(Text("Key")))
  assert_true(audit20_throws(() => s.records() |> ignore))
  s.set(0, 1, Cell::formula("of:=\"header\"", Text("new")))
  assert_true(audit20_throws(() => s.records() |> ignore))
}

///|
test "audit20 R04 atomic multi-cell replacement net budget and array aliases" {
  let b = Workbook::new()
  let s = b.add_sheet("Atomic")
  let long = Array::make(32767, "x").join("")
  s.set_row(0, 0, Array::make(64, Cell::new(Text(long))))
  let replacement = Array::make(65, Cell::new(Text(long)))
  replacement[0] = Cell::new(Empty)
  s.set_row(0, 0, replacement)
  replacement[1] = Cell::new(Number(9.0))
  assert_eq(s.get(0, 1).unwrap().value(), Text(long))
  let before = s.text_units
  assert_true(audit20_throws(() => s.set(1, 0, Cell::new(Text(long)))))
  assert_eq(s.text_units, before)
  assert_eq(s.dimensions(), (1, 65))
  let m = Workbook::new()
  let a = m.add_sheet("Merge")
  a.merge(0, 1, 1, 2)
  let old = m.to_ods()
  assert_true(
    audit20_throws(() => {
      a.set_row(0, 0, [
        Cell::new(Number(2.0)),
        Cell::new(Number(3.0)),
        Cell::new(Number(4.0)),
      ])
    }),
  )
  assert_eq(m.to_ods(), old)
  a.set_row(1000, 0, [])
  assert_eq(a.dimensions(), (1, 3))
}

///|
test "audit20 R05 merge capacity and conflict rollback" {
  let b = Workbook::new()
  let s = b.add_sheet("Merges")
  for r in 0..<256 {
    s.merge(r, 0, 1, 2)
  }
  let before = b.to_ods()
  assert_true(audit20_throws(() => s.merge(256, 0, 1, 2)))
  assert_eq(b.to_ods(), before)
  assert_eq(s.merge_span(255, 0), Some((1, 2)))
  assert_true(s.is_covered(255, 1))
  let c = Workbook::new()
  let t = c.add_sheet("Conflict")
  t.set(1, 1, Cell::new(Empty))
  let old = c.to_ods()
  assert_true(audit20_throws(() => t.merge(0, 0, 2, 2)))
  assert_eq(c.to_ods(), old)
  assert_eq(t.merge_span(0, 0), None)
  assert_false(t.is_covered(1, 1))
}

///|
test "audit20 R06 sheet identity UTF16 boundaries capacity and isolation" {
  let b = Workbook::new()
  let a = b.add_sheet("Sales")
  a.set(0, 0, Cell::new(Number(7.0)))
  assert_true(audit20_throws(() => b.add_sheet("sales") |> ignore))
  let name = Array::make(15, "🧪").join("") + "x"
  let second = b.add_sheet(name)
  second.set(0, 0, Cell::new(Number(9.0)))
  assert_eq(a.get(0, 0).unwrap().value(), Number(7.0))
  for
    invalid in [
      Array::make(16, "🧪").join(""),
      "'edge",
      "edge'",
      "[]",
      "a\u0001",
    ] {
    assert_true(audit20_throws(() => b.add_sheet(invalid) |> ignore))
  }
  for n in 2..<32 {
    b.add_sheet("Sheet\{n}") |> ignore
  }
  assert_true(audit20_throws(() => b.add_sheet("Overflow") |> ignore))
  assert_eq(b.sheet_count(), 32)
  assert_true(b.sheet(-1) is None)
  assert_true(b.sheet(32) is None)
}

///|
test "audit20 R07 extended temporal components exact offset preservation" {
  let good_dt = [
    "2000-02-29T23:59:59.123456789-14:00", "2026-10-31T00:00:00+14:00", "0001-01-01T00:00:00Z",
    "9999-12-31T23:59:59", "2026-01-01T12:00:00-00:00",
  ]
  let bad_dt = [
    "2000-02-29T24:00:00", "2000-02-29T23:59:60", "2000-02-29T23:59:59.1234567890",
    "2000-02-29T23:59:59+14:01", "2000-02-29T23:59:59-15:00", "0000-01-01T00:00:00",
    "2026-01-01t00:00:00Z",
  ]
  let good_d = [
    "P0D", "-PT0S", "P999999999DT999999999H999999999M999999999.123456789S", "PT0001.000S",
    "P1DT2H3M4S",
  ]
  let bad_d = [
    "P1Y", "P1M", "PT1D", "P1DT", "P1D2D", "PT2M1H", "PT1.5H", "PT1.1234567890S",
    "PT1000000000S", "+PT1S", "P",
  ]
  let b = Workbook::new()
  let s = b.add_sheet("Temporal")
  for i, x in good_dt {
    s.set(i, 0, Cell::new(DateTime(x)))
  }
  for i, x in good_d {
    s.set(i, 1, Cell::new(Duration(x)))
  }
  for x in bad_dt {
    assert_true(audit20_throws(() => Cell::new(DateTime(x)) |> ignore))
  }
  for x in bad_d {
    assert_true(audit20_throws(() => Cell::new(Duration(x)) |> ignore))
  }
  let out = read_ods(
      b.to_ods(),
      allow_formatting_loss=true,
      allow_extended_types=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  for i, x in good_dt {
    assert_eq(out.get(i, 0).unwrap().value(), DateTime(x))
  }
  for i, x in good_d {
    assert_eq(out.get(i, 1).unwrap().value(), Duration(x))
  }
}

///|
test "audit20 R08 formula caches immutable style and no coalescing" {
  let b = Workbook::new()
  let s = b.add_sheet("Formula")
  let original = Cell::formula("of:=[.A2]+1", Number(12.0))
  let styled = original.styled(Header)
  assert_eq(original.style(), Plain)
  assert_eq(styled.style(), Header)
  s.set_row(0, 0, [original, original, styled])
  s.set(1, 0, Cell::new(Number(99.0)))
  assert_eq(s.get(0, 0).unwrap().value(), Number(12.0))
  let expr = "of:=\"&<>\""
  s.set(1, 1, Cell::formula(expr, Text("&<>")))
  let xml = b.content_xml()
  assert_false(xml.contains("table:number-columns-repeated=\"3\""))
  let out = read_ods(b.to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(out.get(1, 1).unwrap().expression(), Some(expr))
  for c in 0..<3 {
    assert_eq(out.get(0, c).unwrap().expression(), Some("of:=[.A2]+1"))
    assert_eq(out.get(0, c).unwrap().value(), Number(12.0))
  }
}

///|
test "audit20 R09 cross-unit exact lengths overrides and bounded digits" {
  let b = Workbook::new()
  let s = b.add_sheet("Units")
  for text in ["127mm", "12.7cm", "5in", "360pt", "30pc"] {
    s.set_column_width_length(0, text)
    assert_eq(s.column_width(0), Some(127))
    assert_eq(s.column_width_length(0), Some(text))
  }
  s.set_column_width_length(0, "0.00000000001mm")
  assert_eq(s.column_width(0), None)
  s.set_column_width(0, 2)
  assert_eq(s.column_width_length(0), Some("2mm"))
  let before = b.to_ods()
  for
    bad in [
      "0000000000001mm", "500.000000001mm", "19.685039371in", "1417.32283465pt",
      "118.110236221pc",
    ] {
    assert_true(audit20_throws(() => s.set_column_width_length(0, bad)))
    assert_eq(b.to_ods(), before)
  }
  s.set_row_height_length(0, "0.00000000001mm")
  let out = read_ods(
      b.to_ods(),
      allow_formatting_loss=true,
      preserve_basic_formatting=true,
    )
    .workbook()
    .sheet(0)
    .unwrap()
  assert_eq(out.row_height_length(0), Some("0.00000000001mm"))
}

///|
test "audit20 R10 aggregate grids and escaping byte ceiling recover safely" {
  let b = Workbook::new()
  for i in 0..<4 {
    let s = b.add_sheet("S\{i}")
    s.set(511, 127, Cell::new(Number(i.to_double())))
  }
  b.to_ods() |> ignore
  b.add_sheet("Over") |> ignore
  assert_true(audit20_throws(() => b.content_xml() |> ignore))
  for i in 0..<4 {
    assert_eq(b.sheet(i).unwrap().dimensions(), (512, 128))
  }
  let e = Workbook::new()
  let s = e.add_sheet("Escaping")
  let amp = Array::make(32760, "&").join("")
  for c in 0..<30 {
    s.set(0, c, Cell::new(Text(amp + c.to_string())))
  }
  assert_true(audit20_throws(() => e.to_ods() |> ignore))
  assert_eq(s.get(0, 29).unwrap().value(), Text(amp + "29"))
  s.set_row(0, 0, Array::make(30, Cell::new(Number(1.0))))
  assert_eq(
    read_ods(e.to_ods(), allow_formatting_loss=true)
    .workbook()
    .sheet(0)
    .unwrap()
    .get(0, 29)
    .unwrap()
    .value(),
    Number(1.0),
  )
}
