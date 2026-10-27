///|
/// A recoverable validation error; no user input is inserted as raw XML.
pub suberror OdsError {
  Invalid(String)
} derive(Debug)

///|
/// Formula cache values have the same types as literal values.
/// Date is a Gregorian ODF date in 1..9999, independent of an application's
/// serial date epoch. It does not promise Excel supports historical dates.
pub(all) enum Value {
  Empty
  Text(String)
  Number(Double)
  Percentage(Double)
  Currency(Double, String)
  Duration(String)
  DateTime(String)
  Boolean(Bool)
  Date(Int32, Int32, Int32)
} derive(Eq, Debug)

///|
struct Cell {
  value : Value
  formula : String?
  style : Style
}

///|
/// Validate ODF values; application-specific date ranges are not inferred.
pub fn Cell::new(value : Value) -> Cell raise OdsError {
  validate_value(value)
  { value, formula: None, style: Plain, }
}

///|
/// Optional date policy for Excel's 1900 date system, with an ISO date style.
/// Rejects dates before 1900-01-01 and all invalid Gregorian dates, including
/// Excel's fictional 1900-02-29. Does not configure a reader's date system or
/// guarantee rendering. For historical display, callers may explicitly use
/// Text("0001-01-01"), which has no date arithmetic semantics.
pub fn Cell::excel_1900_date(
  year : Int32,
  month : Int32,
  day : Int32,
) -> Cell raise OdsError {
  let cell = Cell::new(Date(year, month, day))
  if year < 1900 {
    raise Invalid("Excel 1900 date policy requires 1900-01-01 or later")
  }
  cell.styled(DateISO)
}

///|
/// OpenFormula text must begin of:=. This validates storage, not formula syntax.
/// The cache is supplied by the caller and may be stale. Neither editing other
/// cells nor serialization recalculates it; application open/save may retain it.
/// Formula text is stored verbatim, including possible external references.
/// Only pass trusted expressions and manage cache freshness explicitly.
/// Date caches default to DateISO so readers keep the date presentation when
/// evaluating DATE formulas. Callers may still explicitly override the style.
pub fn Cell::formula(expression : String, cache : Value) -> Cell raise OdsError {
  validate_text(expression)
  if !expression.has_prefix("of:=") || expression.length() <= 4 {
    raise Invalid("formula must be nonempty OpenFormula text beginning of:=")
  }
  validate_value(cache)
  if cache == Empty {
    raise Invalid("formula requires a typed nonempty cache")
  }
  let style = match cache {
    Date(_, _, _) => DateISO
    _ => Plain
  }
  { value: cache, formula: Some(expression), style, }
}

///|
/// Returns the stored literal value or caller/imported formula cache. This does
/// not evaluate the formula or assert that its cache matches current operands.
pub fn Cell::value(self : Cell) -> Value {
  self.value
}

///|
pub fn Cell::expression(self : Cell) -> String? {
  self.formula
}

///|
fn validate_text(s : String) -> Unit raise OdsError {
  if s.length() > 32767 {
    raise Invalid("text exceeds 32767 UTF-16 units")
  }
  for c in s {
    let n = c.to_int()
    if !(n == 9 ||
      n == 10 ||
      n == 13 ||
      (n >= 32 && n <= 0xD7FF) ||
      (n >= 0xE000 && n <= 0xFFFD) ||
      (n >= 0x10000 && n <= 0x10FFFF)) {
      raise Invalid("text contains an XML 1.0 forbidden character")
    }
  }
}

///|
fn validate_value(v : Value) -> Unit raise OdsError {
  match v {
    Empty | Boolean(_) => ()
    Text(s) => validate_text(s)
    Percentage(n) | Number(n) =>
      if n.is_nan() || n.is_inf() {
        raise Invalid("number must be finite")
      }
    Currency(n, code) => {
      if n.is_nan() || n.is_inf() {
        raise Invalid("currency amount must be finite")
      }
      if code.length() != 3 {
        raise Invalid("currency requires three uppercase ISO-style letters")
      }
      for c in code {
        if c < 'A' || c > 'Z' {
          raise Invalid("currency requires three uppercase ISO-style letters")
        }
      }
    }
    Duration(text) => validate_duration(text)
    DateTime(text) => validate_datetime(text)
    Date(y, m, d) => {
      if y < 1 || y > 9999 || m < 1 || m > 12 {
        raise Invalid("date is outside Gregorian range")
      }
      let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
      let days = match m {
        2 => if leap { 29 } else { 28 }
        4 | 6 | 9 | 11 => 30
        _ => 31
      }
      if d < 1 || d > days {
        raise Invalid("invalid Gregorian day")
      }
    }
  }
}

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend OdsError with @debug.Debug::{to_repr}

///|
fn extended_digits(
  chars : Array[Char],
  start : Int32,
  count : Int32,
) -> Int32 raise OdsError {
  if start < 0 || count < 1 || count > 9 || start + count > chars.length() {
    raise Invalid("invalid temporal digits")
  }
  let mut n = 0
  for i in start..<(start + count) {
    let c = chars[i]
    if c < '0' || c > '9' {
      raise Invalid("invalid temporal digits")
    }
    n = n * 10 + c.to_int() - 48
  }
  n
}

///|
fn extended_chars(text : String) -> Array[Char] raise OdsError {
  if text.length() > 128 {
    raise Invalid("temporal lexical value exceeds 128 units")
  }
  let chars = []
  for c in text {
    chars.push(c)
  }
  chars
}

///|
// A Gregorian local or offset timestamp. No timezone conversion or arithmetic;
// the exact lexical offset/fraction is stored. Leap seconds/year zero excluded.
fn validate_datetime(text : String) -> Unit raise OdsError {
  let c = extended_chars(text)
  if c.length() < 19 ||
    c[4] != '-' ||
    c[7] != '-' ||
    c[10] != 'T' ||
    c[13] != ':' ||
    c[16] != ':' {
    raise Invalid(
      "dateTime requires YYYY-MM-DDThh:mm:ss with optional fraction/offset",
    )
  }
  validate_value(
    Date(
      extended_digits(c, 0, 4),
      extended_digits(c, 5, 2),
      extended_digits(c, 8, 2),
    ),
  )
  if extended_digits(c, 11, 2) > 23 ||
    extended_digits(c, 14, 2) > 59 ||
    extended_digits(c, 17, 2) > 59 {
    raise Invalid("dateTime clock fields outside supported range")
  }
  let mut at = 19
  if at < c.length() && c[at] == '.' {
    at += 1
    let start = at
    while at < c.length() && c[at] >= '0' && c[at] <= '9' {
      at += 1
    }
    if at - start < 1 || at - start > 9 {
      raise Invalid("dateTime fraction requires 1..9 digits")
    }
  }
  if at == c.length() {
    return
  }
  if c[at] == 'Z' && at + 1 == c.length() {
    return
  }
  if c.length() - at != 6 || (c[at] != '+' && c[at] != '-') || c[at + 3] != ':' {
    raise Invalid("invalid dateTime UTC offset")
  }
  let hour = extended_digits(c, at + 1, 2)
  let minute = extended_digits(c, at + 4, 2)
  if hour > 14 || minute > 59 || (hour == 14 && minute != 0) {
    raise Invalid("dateTime UTC offset outside 14:00")
  }
}

///|
// Day/time duration subset of xsd:duration. Never treats calendar months/years
// as a fixed number of seconds; preserve exact sign/components/fraction.
fn validate_duration(text : String) -> Unit raise OdsError {
  let c = extended_chars(text)
  let mut at = if !c.is_empty() && c[0] == '-' { 1 } else { 0 }
  if at >= c.length() || c[at] != 'P' {
    raise Invalid("duration requires ISO day/time P...T... form")
  }
  at += 1
  let mut time = false
  let mut time_parts = 0
  let mut parts = 0
  let mut order = -1
  while at < c.length() {
    if c[at] == 'T' {
      if time {
        raise Invalid("duplicate duration T separator")
      }
      time = true
      at += 1
      continue
    }
    let start = at
    while at < c.length() && c[at] >= '0' && c[at] <= '9' {
      at += 1
    }
    if at - start < 1 || at - start > 9 {
      raise Invalid("duration component requires 1..9 digits")
    }
    let mut fraction = false
    if at < c.length() && c[at] == '.' {
      fraction = true
      at += 1
      let start = at
      while at < c.length() && c[at] >= '0' && c[at] <= '9' {
        at += 1
      }
      if at - start < 1 || at - start > 9 {
        raise Invalid("duration fraction requires 1..9 digits")
      }
    }
    if at >= c.length() {
      raise Invalid("duration component missing unit")
    }
    let next = match c[at] {
      'D' if !time && !fraction => 0
      'H' if time && !fraction => 1
      'M' if time && !fraction => 2
      'S' if time => 3
      _ => raise Invalid("unsupported duration unit or fraction")
    }
    if next <= order {
      raise Invalid("duration units duplicated or out of order")
    }
    order = next
    at += 1
    parts += 1
    if time {
      time_parts += 1
    }
  }
  if parts == 0 || (time && time_parts == 0) {
    raise Invalid("empty or incomplete duration")
  }
}
