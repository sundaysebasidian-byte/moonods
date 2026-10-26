///|
/// A 1000-row table with a header, text, number, date and boolean columns.
fn sales_workbook(rows : Int) -> @ods.Workbook raise @ods.OdsError {
  let workbook = @ods.Workbook::new()
  let sheet = workbook.add_sheet("sales")
  sheet.set_row(0, 0, [
    @ods.Cell::new(Text("item")).styled(Header),
    @ods.Cell::new(Text("amount")).styled(Header),
    @ods.Cell::new(Text("date")).styled(Header),
    @ods.Cell::new(Text("paid")).styled(Header),
    @ods.Cell::new(Text("note")).styled(Header),
  ])
  for i = 1; i <= rows; i = i + 1 {
    sheet.set_row(i, 0, [
      @ods.Cell::new(Text("item-\{i}")),
      @ods.Cell::new(Number(i.to_double() * 1.25)).styled(Decimal2),
      @ods.Cell::new(Date(2026, 10, i % 28 + 1)).styled(DateISO),
      @ods.Cell::new(Boolean(i % 2 == 0)),
      @ods.Cell::new(Text("备注 \{i}")),
    ])
  }
  workbook
}

///|
fn must_build(rows : Int) -> @ods.Workbook {
  try {
    sales_workbook(rows)
  } catch {
    _ => abort("benchmark workbook must build")
  }
}

///|
fn must_ods(workbook : @ods.Workbook) -> Bytes {
  try {
    workbook.to_ods()
  } catch {
    _ => abort("benchmark workbook must serialize")
  }
}

///|
fn must_read(bytes : Bytes) -> @ods.Workbook {
  try {
    @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
  } catch {
    _ => abort("benchmark package must read back")
  }
}

///|
fn must_csv(sheet : @ods.Sheet) -> String {
  try {
    sheet.to_csv()
  } catch {
    _ => abort("benchmark sheet must export")
  }
}

///|
test "write, read and export a 1000-row sheet" (b : @bench.T) {
  let workbook = sales_workbook(1000)
  let bytes = workbook.to_ods()
  let sheet = must_read(bytes).sheet(0).unwrap()
  assert_eq(sheet.dimensions(), (1001, 5))
  assert_eq(sheet.records(header_row=0).length(), 1000)
  println("package: rows=1000 columns=5 ods=\{bytes.length()}B")
  b.bench(
    name="build_and_write_1000_rows",
    fn() { b.keep(must_ods(must_build(1000))) },
    count=5,
  )
  b.bench(name="read_1000_rows", fn() { b.keep(must_read(bytes)) }, count=5)
  b.bench(name="csv_1000_rows", fn() { b.keep(must_csv(sheet)) }, count=5)
}
