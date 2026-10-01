test "long text limit preserves accepted boundary" {
  let b = StringBuilder()
  for _ in 0..<32768 { b.write_string("x") }
  let ok = b.to_string()
  assert_eq(Cell::new(Text(ok)).units(), 32768)
  assert_true(try { Cell::new(Text(ok + "x")) |> ignore; false } catch { Invalid(_) => true })
  assert_true(try { Cell::formula("of:=" + ok, Number(1.0)) |> ignore; false } catch { Invalid(_) => true })
  assert_true(try { Cell::new(Text("\uFFFF")) |> ignore; false } catch { Invalid(_) => true })
}
test "empty workbook empty sheet and duplicate case" {
  let w = Workbook::new()
  assert_true(try { w.to_ods() |> ignore; false } catch { Invalid(_) => true })
  w.add_sheet("Sheet") |> ignore
  assert_true(w.to_ods().length() > 0)
  assert_true(try { w.add_sheet("sHeEt") |> ignore; false } catch { Invalid(_) => true })
  assert_true(try { w.add_sheet("12345678901234567890123456789012") |> ignore; false } catch { Invalid(_) => true })
}
test "sheet count and cell index limits are transactional" {
  let w = Workbook::new()
  for i in 0..<32 { w.add_sheet("s\{i}") |> ignore }
  assert_true(try { w.add_sheet("extra") |> ignore; false } catch { Invalid(_) => true })
  assert_eq(w.sheet_count(), 32)
  let s = w.sheets[0]
  let c = Cell::new(Number(42.0))
  for (r, col) in [(-1, 0), (0, -1), (1024, 0), (0, 128), (2147483647, 0)] {
    assert_true(try { s.set(r, col, c); false } catch { Invalid(_) => true })
  }
  s.set(1023, 63, c)
  assert_true(try { s.set(0, 64, c); false } catch { Invalid(_) => true })
  assert_true(s.get(0, 64) is None)
  assert_eq((s.rows, s.cols), (1024, 64))
}
test "workbook rendered grid budget" {
  let w = Workbook::new()
  for i in 0..<5 { w.add_sheet("s\{i}").set(1023, 63, Cell::new(Empty)) }
  assert_true(try { w.content_xml() |> ignore; false } catch { Invalid(_) => true })
}
test "sheet text budget replacement accounting" {
  let w = Workbook::new()
  let s = w.add_sheet("s")
  let b = StringBuilder()
  for _ in 0..<32768 { b.write_string("x") }
  let c = Cell::new(Text(b.to_string()))
  for row in 0..<64 { s.set(row, 0, c) }
  assert_eq(s.text_units, 2097152)
  assert_true(try { s.set(64, 0, Cell::new(Text("x"))); false } catch { Invalid(_) => true })
  assert_true(s.get(64, 0) is None)
  s.set(0, 0, Cell::new(Empty))
  s.set(64, 0, c)
  assert_eq(s.text_units, 2097152)
}
test "merge refuses data loss containment adjacent borders and bounds" {
  let w = Workbook::new()
  let s = w.add_sheet("s")
  s.set(1, 1, Cell::new(Text("keep")))
  assert_true(try { s.merge(0, 0, 2, 2); false } catch { Invalid(_) => true })
  assert_eq(s.covered.length(), 0)
  s.merge(2, 0, 2, 2)
  assert_true(try { s.merge(0, 0, 5, 3); false } catch { Invalid(_) => true })
  s.merge(2, 2, 2, 2)
  for (r, c, nr, nc) in [(0, 0, 1, 1), (0, 0, 0, 2), (0, 0, 2, -1), (1023, 0, 2, 2), (0, 127, 1, 2), (0, 0, 2147483647, 2)] {
    assert_true(try { s.merge(r, c, nr, nc); false } catch { Invalid(_) => true })
  }
  assert_eq(s.spans.length(), 2)
}
test "merge count budget" {
  let w = Workbook::new()
  let s = w.add_sheet("s")
  for r in 0..<256 { s.merge(r, 0, 1, 2) }
  assert_true(try { s.merge(256, 0, 1, 2); false } catch { Invalid(_) => true })
  assert_eq(s.spans.length(), 256)
}
test "column errors preserve dimension" {
  let s = Workbook::new().add_sheet("s")
  for (col, mm) in [(-1, 10), (128, 10), (0, 0), (0, 501), (0, 2147483647)] {
    assert_true(try { s.set_column_width(col, mm); false } catch { Invalid(_) => true })
  }
  assert_eq(s.cols, 1)
  s.set_column_width(0, 1)
  s.set_column_width(1, 500)
}
test "same logical workbook is independent of mutation order" {
  let a = Workbook::new()
  let b = Workbook::new()
  let x = a.add_sheet("s")
  let y = b.add_sheet("s")
  let c = Cell::new(Text("中文😀"))
  x.set(0, 0, c); x.set(2, 2, Cell::new(Number(1.0e300)))
  y.set(2, 2, Cell::new(Number(1.0e300))); y.set(0, 0, c)
  x.set_column_width(0, 50); x.set_column_width(1, 35)
  y.set_column_width(1, 35); y.set_column_width(0, 50)
  assert_eq(a.to_ods(), b.to_ods())
}
test "workbook aggregate text boundary before XML serialization" {
  let w = Workbook::new()
  let b = StringBuilder()
  for _ in 0..<32768 { b.write_string("x") }
  let c = Cell::new(Text(b.to_string()))
  for name in ["one", "two"] {
    let s = w.add_sheet(name)
    for r in 0..<64 { s.set(r, 0, c) }
  }
  assert_true(w.content_xml().length() > 0)
  w.add_sheet("three").set(0, 0, Cell::new(Text("x")))
  assert_true(try { w.content_xml() |> ignore; false } catch { Invalid(_) => true })
}
test "serialized UTF8 byte cap preserves boundary and rejects expansion" {
  let b = StringBuilder()
  for _ in 0..<32768 { b.write_string("x") }
  let chunk = b.to_string()
  let xml = XmlOutput::new()
  for _ in 0..<512 { xml.write_string(chunk) }
  assert_eq(xml.data.length(), 16777216)
  assert_true(try { xml.write_string("😀"); false } catch { Invalid(_) => true })
  assert_eq(xml.data.length(), 16777216)
}
test "malformed UTF16 and finite numeric edges" {
  for s in [String::from_array([(0xD800).unsafe_to_char()]), String::from_array([(0xDC00).unsafe_to_char()]), "\uFFFE", "\u0001"] {
    assert_true(try { Cell::new(Text(s)) |> ignore; false } catch { Invalid(_) => true })
  }
  assert_true(try { Cell::new(Number(-1.0 / 0.0)) |> ignore; false } catch { Invalid(_) => true })
  for v in [Number(-0.0), Number(1.0e300), Number(1.0e-300), Date(1, 1, 1), Date(9999, 12, 31), Date(2000, 2, 29)] {
    assert_eq(Cell::new(v).value(), v)
  }
  for v in [Date(2026, 4, 31), Date(2026, 1, 0), Date(10000, 1, 1), Date(2100, 2, 29)] {
    assert_true(try { Cell::new(v) |> ignore; false } catch { Invalid(_) => true })
  }
}
test "formula cache remains caller supplied including inconsistent values" {
  let c = Cell::formula("of:=1+1", Number(99.0))
  assert_eq(c.value(), Number(99.0))
  assert_true(c.xml("").contains("office:value=\"99\""))
  assert_eq(Cell::formula("of:=FALSE()", Boolean(false)).value(), Boolean(false))
}
