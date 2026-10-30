///|
test "nonfinite ODF tokens are unsupported values not malformed lexical forms" {
  for raw in ["INF", "-INF", "NaN", "  INF\t"] {
    let message = try {
      read_finite_double(raw) |> ignore
      "accepted"
    } catch {
      Invalid(s) => s
    }
    assert_eq(
      message, "unsupported non-finite ODF numeric value; finite numbers required",
    )
  }
  for raw in ["+INF", "inf", "nan", "-NaN", "I NF", "Infinity"] {
    let message = try {
      read_finite_double(raw) |> ignore
      "accepted"
    } catch {
      Invalid(s) => s
    }
    assert_eq(message, "invalid ODF numeric lexical form")
  }
  assert_eq(read_finite_double(" +1.25 "), 1.25)
}
