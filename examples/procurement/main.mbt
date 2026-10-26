///|
// Entirely synthetic procurement review. Monetary inputs are integer cents;
// these exact quarter/half-unit examples do not establish decimal accounting.
extern "js" fn setting(name : String) -> String =
  #| name => process.env[name] || ''

///|
extern "js" fn load(path : String) -> Bytes =
  #| path => new Uint8Array(require('node:fs').readFileSync(path))

///|
extern "js" fn save(name : String, bytes : Bytes) -> Unit =
  #| (name, bytes) => require('node:fs').writeFileSync(require('node:path').join(process.env.REPORT_OUTPUT, name), bytes)

///|
extern "js" fn save_csv(text : String) -> Unit =
  #| text => require('node:fs').writeFileSync(require('node:path').join(process.env.REPORT_OUTPUT, 'procurement.csv'), text, 'utf8')

///|
fn check(book : @ods.Workbook) -> Unit raise {
  assert_eq(book.sheet_count(), 3)
  let detail = book.sheet(0).unwrap()
  assert_eq(detail.name(), "采购明细")
  assert_eq(detail.records().length(), 4)
  assert_eq(
    detail.get(1, 2).unwrap().value(),
    @ods.Value::Text("示教传感器😀"),
  )
  assert_eq(detail.get(1, 5).unwrap().value(), @ods.Value::Number(376.5))
  assert_eq(detail.get(1, 6).unwrap().value(), @ods.Value::Date(2026, 10, 1))
  assert_eq(detail.get(1, 7).unwrap().value(), @ods.Value::Boolean(true))
  assert_eq(detail.get(2, 8).unwrap().value(), @ods.Value::Empty)
  assert_eq(detail.get(3, 8).unwrap().value(), @ods.Value::Text(""))
  for r in 1..<5 {
    assert_eq(
      detail.get(r, 5).unwrap().expression(),
      Some("of:=[.D\{r + 1}]*[.E\{r + 1}]"),
    )
  }
  let summary = book.sheet(1).unwrap()
  assert_eq(summary.name(), "预算复核")
  assert_eq(summary.get(1, 2).unwrap().value(), @ods.Value::Number(536.5))
  assert_eq(summary.get(2, 2).unwrap().value(), @ods.Value::Number(266.5))
  assert_eq(summary.get(1, 3).unwrap().value(), @ods.Value::Number(63.5))
  assert_eq(summary.get(2, 3).unwrap().value(), @ods.Value::Number(33.5))
}

///|
fn make_report() -> @ods.Workbook raise {
  let book = @ods.Workbook::new()
  let detail = book.add_sheet("采购明细")
  detail.set_row(
    0,
    0,
    [
      "订单", "部门", "品目", "数量", "单价", "含税小计", "到货日期",
      "验收", "备注",
    ].map(s => @ods.Cell::new(Text(s)).styled(Header)),
  )
  let departments = ["研发", "运营", "研发", "运营"]
  let items = ["示教传感器😀", "展示纸", "校准件", "包装材料"]
  let quantities = [3, 12, 2, 5]
  let unit_cents = [12550, 1825, 8000, 950]
  let notes : Array[@ods.Value] = [
    Text("含引号\"样品\",\n第二行"),
    Empty,
    Text(""),
    Text("完全合成，无真实供应商"),
  ]
  for i in 0..<4 {
    let r = i + 1
    detail.set_row(r, 0, [
      @ods.Cell::new(Text("SYN-202610-00\{r}")),
      @ods.Cell::new(Text(departments[i])),
      @ods.Cell::new(Text(items[i])),
      @ods.Cell::new(Number(quantities[i].to_double())),
      @ods.Cell::new(Number(unit_cents[i].to_double() / 100.0)).styled(Decimal2),
      @ods.Cell::formula(
        "of:=[.D\{r + 1}]*[.E\{r + 1}]",
        Number((quantities[i] * unit_cents[i]).to_double() / 100.0),
      ).styled(Decimal2),
      @ods.Cell::new(Date(2026, 10, i * 2 + 1)).styled(DateISO),
      @ods.Cell::new(Boolean(i % 2 == 0)),
      @ods.Cell::new(notes[i]),
    ])
  }
  detail.set_column_width(2, 42)
  detail.set_column_width(8, 55)
  let summary = book.add_sheet("预算复核")
  summary.set_row(
    0,
    0,
    ["部门", "预算", "采购额", "剩余预算"].map(s => {
      @ods.Cell::new(Text(s)).styled(Header)
    }),
  )
  summary.set_row(1, 0, [
    @ods.Cell::new(Text("研发")),
    @ods.Cell::new(Number(600.0)),
    @ods.Cell::new(Number(536.5)),
    @ods.Cell::formula("of:=[.B2]-[.C2]", Number(63.5)),
  ])
  summary.set_row(2, 0, [
    @ods.Cell::new(Text("运营")),
    @ods.Cell::new(Number(300.0)),
    @ods.Cell::new(Number(266.5)),
    @ods.Cell::formula("of:=[.B3]-[.C3]", Number(33.5)),
  ])
  let notes_sheet = book.add_sheet("使用说明")
  notes_sheet.set(
    0,
    0,
    @ods.Cell::new(
      Text(
        "全部为合成采购记录；无实际采用或财务准确性承诺。",
      ),
    ),
  )
  notes_sheet.set(
    1,
    0,
    @ods.Cell::new(
      Text(
        "公式由调用者提供可信表达式和缓存；保存不会承诺重算。CSV丢失公式、类型、空值区别和样式。",
      ),
    ),
  )
  check(book)
  book
}

///|
fn main raise {
  let input = setting("REPORT_READBACK")
  let book = if input == "" {
    make_report()
  } else {
    let imported = @ods.read_ods(load(input), allow_formatting_loss=true)
    println(
      "IMPORT_DIAGNOSTICS=\{imported.diagnostics().length()}; formatting loss explicitly accepted",
    )
    imported.workbook()
  }
  check(book)
  let bytes = book.to_ods()
  let again = @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
  check(again)
  save(if input == "" { "procurement.ods" } else { "readback.ods" }, bytes)
  save_csv(
    book
    .sheet(0)
    .unwrap()
    .to_csv(use_formula_cache=true, reject_formula_like_text=true),
  )
  println(
    "PROCUREMENT_TYPED_ROUNDTRIP_OK total=803; budget_remaining=97; synthetic_only=true; formula_recalculation=false",
  )
}
