///|
test "business adapter supports different and empty input lists" {
  let w = sales_report([
    { product: "不同批次", quantity: 3.0, amount: 7.5, },
  ])
  assert_eq(w.sheet_count(), 1)
  let empty = sales_report([])
  assert_true(empty.to_ods().length() > 0)
  assert_true(w.to_ods() != empty.to_ods())
}

///|
test "laboratory adapter supports empty observations and arbitrary metadata" {
  let w = laboratory_report([], "另一个实验来源")
  assert_eq(w.sheet_count(), 2)
  assert_true(w.content_xml().contains("另一个实验来源"))
  assert_true(w.to_ods().length() > 0)
}

///|
test "caller cache survives even when inconsistent with formula" {
  let w = declaration_report([1.0, 2.0], example_declarations())
  assert_true(w.content_xml().contains("office:value=\"99\""))
  assert_true(w.to_ods().length() > 0)
}

///|
test "same input produces same package in downstream module" {
  assert_eq(
    sales_report(example_sales()).to_ods(),
    sales_report(example_sales()).to_ods(),
  )
}
