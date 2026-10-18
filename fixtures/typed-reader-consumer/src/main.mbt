// Independent consumer: only MoonODS public API. File adapters are JS-only;
// the library's ZIP/XML/typed implementation is pure MoonBit.

///|
extern "js" fn load_input() -> String =
  #| () => require('node:fs').readFileSync(process.env.ODS_INPUT).toString('base64')

///|
extern "js" fn save_output(data : String) =
  #| data => require('node:fs').writeFileSync(process.env.ODS_OUTPUT, Buffer.from(data, 'base64'))

///|
fn main raise {
  let raw = load_input()
  let imported = @ods.read_ods(
    @base64.decode(raw[:]),
    allow_formatting_loss=true,
  )
  let book = imported.workbook()
  let sheet = book.sheet(0).unwrap()
  assert_eq(sheet.name(), "Types")
  assert_eq(sheet.get(0, 1).unwrap().value(), @ods.Value::Boolean(true))
  assert_eq(sheet.get(0, 2).unwrap().value(), @ods.Value::Date(2024, 2, 29))
  assert_eq(sheet.get(0, 4).unwrap().value(), @ods.Value::Text(""))
  assert_eq(sheet.get(0, 5).unwrap().value(), @ods.Value::Empty)
  sheet.set(1, 0, @ods.Cell::new(Number(8.5)))
  let output = book.to_ods()
  let check = @ods.read_ods(output, allow_formatting_loss=true).workbook()
  assert_eq(
    check.sheet(0).unwrap().get(1, 0).unwrap().value(),
    @ods.Value::Number(8.5),
  )
  assert_eq(check.sheet(1).unwrap().merge_span(0, 0), Some((2, 2)))
  for d in imported.diagnostics() {
    println("\{d.code}|\{d.sheet}|\{d.row}|\{d.col}|\{d.message}")
  }
  save_output(@base64.encode(output[:]))
  println("PUBLIC_CONSUMER_TYPED_EDIT_WRITE_REREAD_OK")
}
