test "ZIP first header and determinism" {
  let w = Workbook::new()
  w.add_sheet("Sheet1").set(0, 0, Cell::new(Text("中文")))
  let b = w.to_ods()
  assert_eq(b[:4].to_bytes(), b"PK\x03\x04")
  assert_eq(b[8], b'\x00')
  assert_eq(b[28], b'\x00')
  assert_eq(b[29], b'\x00')
  assert_eq(b[30:38].to_bytes(), b"mimetype")
  assert_eq(b, w.to_ods())
}
