///|
test "ZIP first header and determinism" {
  let w = Workbook::new()
  w.add_sheet("Sheet1").set(0, 0, Cell::new(Text("中文")))
  let b = w.to_ods()
  assert_eq(b[:4].to_owned(), b"PK\x03\x04")
  assert_eq(b[8], b'\x00')
  assert_eq(b[28], b'\x00')
  assert_eq(b[29], b'\x00')
  assert_eq(b[30:38].to_owned(), b"mimetype")
  assert_eq(b, w.to_ods())
}

///|
test "ZIP32 complete envelope budget includes both headers and rejects excess" {
  // Synthetic private envelope, not a public ODS or arbitrary-assets API.
  // One one-byte ZIP name costs 31 local + 47 central + 22 EOCD bytes.
  let limit = 33554432
  let exact = Bytes::make(limit - 100, b'\x00')
  assert_eq(stored_package([("p", exact)]).length(), limit)
  assert_true(
    try {
      stored_package([("p", Bytes::make(limit - 99, b'\x00'))]) |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
  assert_true(
    try {
      stored_package([("p", Bytes::make(limit + 1, b'\x00'))]) |> ignore
      false
    } catch {
      Invalid(_) => true
    },
  )
}
