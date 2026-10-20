///|
extern "js" fn csv_input() -> String =
  #| () => require('node:fs').readFileSync(process.env.ODS_VALUE_INPUT, 'utf8')

///|
extern "js" fn save_ods(bytes : Bytes) =
  #| bytes => require('node:fs').writeFileSync(process.env.ODS_VALUE_OUTPUT + '/value.ods', bytes)

///|
extern "js" fn save_csv(text : String) =
  #| text => require('node:fs').writeFileSync(process.env.ODS_VALUE_OUTPUT + '/export.csv', text)

///|
extern "js" fn readback_path() -> String =
  #| () => process.env.ODS_VALUE_READBACK || ''

///|
extern "js" fn read_ods_bytes(path : String) -> Bytes =
  #| path => new Uint8Array(require('node:fs').readFileSync(path))

///|
fn check(book : @ods.Workbook) -> Unit raise {
  assert_eq(book.sheet_count(), 2)
  let rows = book.sheet(0).unwrap().records()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].row, 1)
  assert_eq(rows[0].values["Name"], @ods.Value::Text("中文"))
  assert_eq(rows[0].values["Note"], @ods.Value::Text("comma,quote\"and\nline"))
  assert_eq(rows[0].values["Empty"], @ods.Value::Text(""))
  assert_eq(rows[1].values["Name"], @ods.Value::Text("=1+2"))
  let typed = book.sheet(1).unwrap().records()[0]
  assert_eq(typed.values["Number"], @ods.Value::Number(7.5))
  assert_eq(typed.values["Date"], @ods.Value::Date(2024, 2, 29))
  assert_eq(typed.values["Bool"], @ods.Value::Boolean(true))
  assert_eq(typed.values["Blank"], @ods.Value::Empty)
  assert_eq(typed.values["EmptyString"], @ods.Value::Text(""))
}

///|
fn main raise {
  let readback = readback_path()
  if readback != "" {
    let book = @ods.read_ods(
      read_ods_bytes(readback),
      allow_formatting_loss=true,
    ).workbook()
    check(book)
    assert_eq(
      book.sheet(0).unwrap().to_csv(),
      @ods.Workbook::new().add_csv_sheet("Expected", csv_input()).to_csv(),
    )
    println("VALUE_PUBLIC_OFFICE_READBACK_OK")
    return
  }
  let book = @ods.Workbook::new()
  let csv = book.add_csv_sheet("CSV", csv_input())
  let sheet = book.add_sheet("Typed")
  sheet.set_row(
    0,
    0,
    ["Name", "Number", "Date", "Bool", "Blank", "EmptyString"].map(s => {
      @ods.Cell::new(@ods.Value::Text(s))
    }),
  )
  sheet.set_row(1, 0, [
    @ods.Cell::new(@ods.Value::Text("sample")),
    @ods.Cell::new(@ods.Value::Number(7.5)),
    @ods.Cell::new(@ods.Value::Date(2024, 2, 29)),
    @ods.Cell::new(@ods.Value::Boolean(true)),
    @ods.Cell::new(@ods.Value::Empty),
    @ods.Cell::new(@ods.Value::Text("")),
  ])
  check(book)
  let bytes = book.to_ods()
  check(@ods.read_ods(bytes, allow_formatting_loss=true).workbook())
  save_csv(csv.to_csv())
  save_ods(bytes)
  println("VALUE_PUBLIC_CSV_RECORDS_ODS_ROUNDTRIP_OK")
}
