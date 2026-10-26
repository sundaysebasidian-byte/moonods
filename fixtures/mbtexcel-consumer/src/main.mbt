///|
extern "js" fn load_input() -> String =
  #| () => require('node:fs').readFileSync(process.env.ODS_INPUT).toString('base64')

///|
extern "js" fn save_output(data : String) =
  #| data => require('node:fs').writeFileSync(process.env.XLSX_OUTPUT, Buffer.from(data, 'base64'))

///|
suberror ConversionError {
  Unsupported(String)
}

///|
fn convert(book : @ods.Workbook, cache_only~ : Bool = false) -> Bytes raise {
  let output = @xlsx.Workbook::new()
  // Validate before making a partial workbook. ODS formulas are not Excel formulas.
  for index in 0..<book.sheet_count() {
    let sheet = book.sheet(index).unwrap()
    let (rows, cols) = sheet.dimensions()
    for row in 0..<rows {
      for col in 0..<cols {
        if sheet.get(row, col) is Some(cell) {
          if cell.expression() is Some(_) && !cache_only {
            raise Unsupported("formula export requires explicit cache_only")
          }
          if cell.value() is Date(year, _, _) && year < 1900 {
            raise Unsupported(
              "Excel 1900 date system cannot preserve this date",
            )
          }
        }
      }
    }
  }
  let expected : Array[(String, Int32, Int32, @xlsx.CellValue)] = []
  for index in 0..<book.sheet_count() {
    let sheet = book.sheet(index).unwrap()
    let name = sheet.name()
    let _ = output.add_sheet(name)
    let (rows, cols) = sheet.dimensions()
    for row in 0..<rows {
      for col in 0..<cols {
        if !sheet.is_covered(row, col) && sheet.get(row, col) is Some(cell) {
          if cell.expression() is Some(_) {
            println("FORMULA_DROPPED|\{name}|\{row}|\{col}")
          }
          let value = match cell.value() {
            Empty => None
            Text(text) => Some(@xlsx.CellValue::String(text))
            Number(number) => Some(@xlsx.CellValue::Numeric(number))
            Boolean(value) => Some(@xlsx.CellValue::Bool(value))
            Date(year, month, day) =>
              Some(
                @xlsx.CellValue::Numeric(
                  @xlsx.time_to_excel_date(@time.date_time(year, month, day)),
                ),
              )
          }
          if value is Some(value) {
            output.set_cell_value_rc(name[:], row + 1, col + 1, value)
            expected.push((name, row + 1, col + 1, value))
          }
          if sheet.merge_span(row, col) is Some((height, width)) {
            output.merge_cell(
              name[:],
              @xlsx.coordinates_to_cell_name(col + 1, row + 1)[:],
              @xlsx.coordinates_to_cell_name(col + width, row + height)[:],
            )
          }
        }
      }
    }
  }
  let bytes = @xlsx.write(output)
  let reread = @xlsx.read(bytes[:])
  for (name, row, col, value) in expected {
    let actual = reread.get_cell_value_raw_rc(name[:], row, col).unwrap()
    match (value, actual) {
      (String(a), String(b)) => assert_eq(a, b)
      (Bool(a), Bool(b)) => assert_eq(a, b)
      (Numeric(a), Numeric(b)) => {
        assert_eq(a, b)
        if a == 0.0 && 1.0 / a != 1.0 / b {
          println("NUMBER_SIGNED_ZERO_CHANGED|\{name}|\{row - 1}|\{col - 1}")
        }
      }
      _ => fail("XLSX typed value changed")
    }
  }
  println("SAME_MODULE_TYPED_VALUES_VERIFIED=\{expected.length()}")
  bytes
}

///|
fn main raise {
  let ordered = @ods.Workbook::new()
  ordered.add_sheet("Before").set(0, 0, @ods.Cell::new(Text("first")))
  ordered.add_sheet("Sheet1").set(0, 0, @ods.Cell::excel_1900_date(1900, 1, 1))
  let ordered_bytes = convert(ordered)
  let ordered_read = @xlsx.read(ordered_bytes[:])
  assert_eq(ordered_read.get_sheet_list(), ["Before", "Sheet1"])
  match ordered_read.get_cell_value_raw_rc("Sheet1", 1, 1).unwrap() {
    Numeric(value) => assert_eq(value, 1.0)
    _ => fail("Excel 1900 boundary date changed")
  }
  println("SHEET1_ORDER_AND_1900_DATE_VERIFIED")
  let raw = load_input()
  let imported = @ods.read_ods(
    @base64.decode(raw[:]),
    allow_formatting_loss=true,
  )
  let book = imported.workbook()
  book.sheet(0).unwrap().set(1, 0, @ods.Cell::new(Number(8.5)))
  let edited = @ods.read_ods(book.to_ods(), allow_formatting_loss=true).workbook()
  let rejected = try {
    let _ = convert(edited)
    false
  } catch {
    Unsupported(_) => true
    error => raise error
  }
  assert_true(rejected)
  println("FORMULA_DEFAULT_REJECTION_VERIFIED")
  let bytes = convert(edited, cache_only=true)
  save_output(@base64.encode(bytes[:]))
}
