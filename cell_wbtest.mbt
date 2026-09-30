test "typed literals and formula cache" {
  assert_eq(Cell::new(Text("中文<&")).value(), Text("中文<&"))
  assert_eq(Cell::new(Date(2000, 2, 29)).value(), Date(2000, 2, 29))
  assert_eq(Cell::formula("of:=SUM([.A1:.A2])", Number(3.0)).expression(), Some("of:=SUM([.A1:.A2])"))
}
test "finite numbers and Gregorian dates" {
  let bad = [Number(1.0 / 0.0), Number(0.0 / 0.0), Date(1900, 2, 29), Date(2026, 13, 1), Date(0, 1, 1)]
  for v in bad {
    let rejected = try { Cell::new(v) |> ignore; false } catch { Invalid(_) => true }
    assert_true(rejected)
  }
}
test "reject XML controls and invalid formula storage" {
  assert_true(try { Cell::new(Text("a\u0000b")) |> ignore; false } catch { Invalid(_) => true })
  assert_true(try { Cell::formula("=1+2", Number(3.0)) |> ignore; false } catch { Invalid(_) => true })
  assert_true(try { Cell::formula("of:=1+2", Empty) |> ignore; false } catch { Invalid(_) => true })
}
