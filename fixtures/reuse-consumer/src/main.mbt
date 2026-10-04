// Independent downstream module. All data are synthetic. MIT; AI-assisted.
// Only this consumer's file adapter uses Node; the writer returns Bytes.

///|
#cfg(target="js")
extern "js" fn save(name : String, data : String) =
  #| (name, data) => { const fs = require('node:fs'); fs.mkdirSync('generated', {recursive:true}); fs.writeFileSync('generated/'+name+'.ods', Buffer.from(data, 'base64')); }

///|
struct Sale {
  product : String
  quantity : Double
  amount : Double
}

///|
fn sales_report(items : Array[Sale]) -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("业务汇总")
  s.set(
    0,
    0,
    @ods.Cell::new(Text("下游提供的商品清单")).styled(Header),
  )
  s.merge(0, 0, 1, 3)
  for c, label in ["商品", "数量", "金额"] {
    s.set(1, c, @ods.Cell::new(Text(label)).styled(Header))
  }
  let mut quantity = 0.0
  let mut amount = 0.0
  for i, item in items {
    s.set_row(i + 2, 0, [
      @ods.Cell::new(Text(item.product)),
      @ods.Cell::new(Number(item.quantity)),
      @ods.Cell::new(Number(item.amount)).styled(Decimal2),
    ])
    quantity += item.quantity
    amount += item.amount
  }
  // Aggregation belongs to the consumer; MoonODS only stores typed values.
  s.set_row(items.length() + 2, 0, [
    @ods.Cell::new(Text("合计")).styled(Highlight),
    @ods.Cell::new(Number(quantity)),
    @ods.Cell::new(Number(amount)).styled(Decimal2),
  ])
  for c, mm in [65, 20, 35] {
    s.set_column_width(c, mm)
  }
  w
}

///|
struct Sample {
  date : (Int, Int, Int)
  reading : Double
  accepted : Bool
  note : String
}

///|
fn laboratory_report(
  samples : Array[Sample],
  source : String,
) -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("测量")
  for c, label in ["日期", "测量值", "通过", "备注"] {
    s.set(0, c, @ods.Cell::new(Text(label)).styled(Header))
  }
  for i, sample in samples {
    let (y, m, d) = sample.date
    s.set_row(i + 1, 0, [
      @ods.Cell::new(Date(y, m, d)).styled(DateISO),
      @ods.Cell::new(Number(sample.reading)),
      @ods.Cell::new(Boolean(sample.accepted)),
      @ods.Cell::new(Text(sample.note)),
    ])
  }
  let metadata = w.add_sheet("记录来源")
  metadata.set(0, 0, @ods.Cell::new(Text(source)))
  metadata.set(1, 0, @ods.Cell::new(Empty))
  metadata.set(1, 1, @ods.Cell::new(Text("")))
  s.set_column_width(3, 100)
  w
}

///|
fn declaration_report(
  inputs : Array[Double],
  declarations : Array[(String, @ods.Value)],
) -> @ods.Workbook raise @ods.OdsError {
  let w = @ods.Workbook::new()
  let s = w.add_sheet("调用方缓存")
  for r, value in inputs {
    s.set(r, 0, @ods.Cell::new(Number(value)))
  }
  for r, entry in declarations {
    let (expression, cache) = entry
    s.set(r, 1, @ods.Cell::formula(expression, cache))
  }
  w
}

///|
fn example_sales() -> Array[Sale] {
  [
    { product: "教学套件 <A>&B", quantity: 2.0, amount: 50.0, },
    { product: "耗材", quantity: 5.0, amount: 12.5, },
  ]
}

///|
fn example_samples() -> Array[Sample] {
  [
    {
      date: (2024, 2, 29),
      reading: -2.5,
      accepted: true,
      note: " 中文  空白\t制表\n下一行 😀 ",
    },
    { date: (2026, 10, 1), reading: 0.0, accepted: false, note: "", },
  ]
}

///|
fn example_declarations() -> Array[(String, @ods.Value)] raise @ods.OdsError {
  [
    // Deliberately inconsistent sum: proves cache is provided, not evaluated.
    ("of:=SUM([.A1:.A2])", Number(99.0)),
    ("of:=[.A1]<[.A2]", Boolean(true)),
    ("of:=\"下游中文 & 缓存\"", Text("下游中文 & 缓存")),
    ("of:=DATE(2026;10;1)", @ods.Cell::excel_1900_date(2026, 10, 1).value()),
  ]
}

///|
#cfg(target="js")
fn main raise {
  save("business", @base64.encode(sales_report(example_sales()).to_ods()[:]))
  save(
    "laboratory",
    @base64.encode(
      laboratory_report(example_samples(), "合成批次 LAB-02").to_ods()[:],
    ),
  )
  save(
    "declarations",
    @base64.encode(
      declaration_report([1.0, 2.0], example_declarations()).to_ods()[:],
    ),
  )
  println("Independent module generated three ODS files from supplied inputs")
}

///|
#cfg(target="wasm-gc")
fn main raise {
  let business = sales_report(example_sales()).to_ods()
  let laboratory = laboratory_report(example_samples(), "合成批次 LAB-02").to_ods()
  let declarations = declaration_report([1.0, 2.0], example_declarations()).to_ods()
  println("MOONODS_ODS:business:\{@base64.encode(business[:])}")
  println("MOONODS_ODS:laboratory:\{@base64.encode(laboratory[:])}")
  println("MOONODS_ODS:declarations:\{@base64.encode(declarations[:])}")
}
