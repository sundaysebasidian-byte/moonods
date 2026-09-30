/// A recoverable validation error; no user input is inserted as raw XML.
pub suberror OdsError { Invalid(String) } derive(Debug)

/// Formula cache values have the same types as literal values.
pub(all) enum Value {
  Empty
  Text(String)
  Number(Double)
  Boolean(Bool)
  Date(Int, Int, Int)
} derive(Eq, Debug)

pub struct Cell {
  value : Value
  formula : String?
}

pub fn Cell::new(value : Value) -> Cell raise OdsError {
  validate_value(value)
  { value, formula: None }
}

/// OpenFormula text must begin of:=. This validates storage, not formula syntax.
pub fn Cell::formula(expression : String, cache : Value) -> Cell raise OdsError {
  validate_text(expression)
  if !expression.has_prefix("of:=") || expression.length() <= 4 {
    raise Invalid("formula must be nonempty OpenFormula text beginning of:=")
  }
  validate_value(cache)
  if cache == Empty { raise Invalid("formula requires a typed nonempty cache") }
  { value: cache, formula: Some(expression) }
}

pub fn Cell::value(self : Cell) -> Value { self.value }
pub fn Cell::expression(self : Cell) -> String? { self.formula }

fn validate_text(s : String) -> Unit raise OdsError {
  if s.length() > 32768 { raise Invalid("text exceeds 32768 UTF-16 units") }
  for c in s {
    let n = c.to_int()
    if !(n == 9 || n == 10 || n == 13 || (n >= 32 && n <= 0xD7FF) || (n >= 0xE000 && n <= 0xFFFD) || (n >= 0x10000 && n <= 0x10FFFF)) {
      raise Invalid("text contains an XML 1.0 forbidden character")
    }
  }
}

fn validate_value(v : Value) -> Unit raise OdsError {
  match v {
    Empty | Boolean(_) => ()
    Text(s) => validate_text(s)
    Number(n) => if n.is_nan() || n.is_inf() { raise Invalid("number must be finite") }
    Date(y, m, d) => {
      if y < 1 || y > 9999 || m < 1 || m > 12 { raise Invalid("date is outside Gregorian range") }
      let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
      let days = match m { 2 => if leap { 29 } else { 28 }; 4 | 6 | 9 | 11 => 30; _ => 31 }
      if d < 1 || d > days { raise Invalid("invalid Gregorian day") }
    }
  }
}

pub extend Value with Eq::{equal, not_equal}
pub extend Value with @debug.Debug::{to_repr}
pub extend OdsError with @debug.Debug::{to_repr}
