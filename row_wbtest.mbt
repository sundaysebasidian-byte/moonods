///|
test "typed row write and empty no-op preserve sparse dimensions" {
  let w = Workbook::new()
  let s = w.add_sheet("整行")
  s.set_row(0, 0, [
    Cell::new(Text("中文<&> 😀")),
    Cell::new(Number(-2.5)),
    Cell::new(Boolean(false)),
    Cell::new(Date(2024, 2, 29)),
    Cell::new(Empty),
    Cell::formula("of:=1+1", Number(99.0)),
  ])
  assert_eq(s.get(0, 0).unwrap().value(), Text("中文<&> 😀"))
  assert_eq(s.get(0, 5).unwrap().value(), Number(99.0))
  assert_eq((s.rows, s.cols), (1, 6))
  let before = w.to_ods()
  s.set_row(1023, 127, [])
  assert_eq(w.to_ods(), before)
  for (r, c) in [(-1, 0), (1024, 0), (0, -1), (0, 128)] {
    assert_true(
      try {
        s.set_row(r, c, [])
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_eq(w.to_ods(), before)
  }
}

///|
test "later covered cell and row overflow reject whole batch" {
  let w = Workbook::new()
  let s = w.add_sheet("合并")
  s.set(0, 0, Cell::new(Text("保留")))
  s.merge(0, 1, 1, 2)
  let before = w.to_ods()
  let c = Cell::new(Text("新值"))
  for (r, col, values) in [(0, 0, [c, c, c]), (1, 127, [c, c])] {
    assert_true(
      try {
        s.set_row(r, col, values)
        false
      } catch {
        Invalid(_) => true
      },
    )
    assert_eq(w.to_ods(), before)
  }
  assert_eq(s.get(0, 0).unwrap().value(), Text("保留"))
  assert_true(s.get(0, 1) is None)
  s.set_row(0, 0, [c, c])
  assert_eq(s.get(0, 1).unwrap().value(), Text("新值"))
  let large = Workbook::new()
  let sheet = large.add_sheet("网格")
  sheet.set(1023, 63, Cell::new(Empty))
  let saved = large.to_ods()
  assert_true(
    try {
      sheet.set_row(0, 63, [c, c])
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(large.to_ods(), saved)
}

///|
test "batch net replacement budget succeeds where partial writes would fail" {
  let w = Workbook::new()
  let s = w.add_sheet("预算")
  let b = StringBuilder()
  for _ in 0..<32767 {
    b.write_string("x")
  }
  let c = Cell::new(Text(b.to_string()))
  for row in 0..<64 {
    s.set(row, 1, c)
  }
  s.set(64, 1, Cell::new(Text("x".repeat(64))))
  assert_eq(s.text_units, 2097152)
  assert_true(
    try {
      s.set(0, 0, c)
      false
    } catch {
      Invalid(_) => true
    },
  )
  s.set_row(0, 0, [c, Cell::new(Empty)])
  assert_eq(s.text_units, 2097152)
  assert_eq(s.get(0, 0).unwrap().value(), c.value())
  assert_eq(s.get(0, 1).unwrap().value(), Empty)
  let before = w.to_ods()
  assert_true(
    try {
      s.set_row(65, 0, [c, c])
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_eq(w.to_ods(), before)
  assert_eq((s.rows, s.cols), (65, 2))
}
