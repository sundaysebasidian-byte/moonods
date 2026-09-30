test "workbook grid names and deterministic traversal" {
  let w = Workbook::new()
  let s = w.add_sheet("销售 & 数据")
  s.set(2, 1, Cell::new(Number(42.0)))
  assert_eq(w.sheet_count(), 1)
  assert_eq(s.name(), "销售 & 数据")
  assert_true(w.content_xml().contains("table:name=\"销售 &amp; 数据\""))
  assert_eq(w.content_xml(), w.content_xml())
  assert_true(try { w.add_sheet("销售 & 数据") |> ignore; false } catch { Invalid(_) => true })
  for name in ["", "   ", "a/b", "a\\b", "a:b", "a?b", "a*b", "[a]", "'a", "a'"] {
    assert_true(try { w.add_sheet(name) |> ignore; false } catch { Invalid(_) => true })
  }
  assert_true(try { s.set(-1, 0, Cell::new(Empty)); false } catch { Invalid(_) => true })
  assert_true(try { s.set(1024, 0, Cell::new(Empty)); false } catch { Invalid(_) => true })
}
