// XML Schema whiteSpace=collapse uses XML S, not Unicode whitespace.

///|
fn read_xsd_collapse(raw : String) -> String {
  let out = StringBuilder()
  let mut seen = false
  let mut pending = false
  for c in raw {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      pending = seen
    } else {
      if pending {
        out.write_char(' ')
      }
      out.write_char(c)
      seen = true
      pending = false
    }
  }
  out.to_string()
}

///|
fn read_xsd_positive(raw : String, max : Int32) -> Int32 raise OdsError {
  let raw = read_xsd_collapse(raw)
  let digits = if raw.has_prefix("+") { raw[1:].to_owned() } else { raw }
  read_positive(digits, max)
}

///|
fn read_xsd_nonnegative(raw : String, max : Int32) -> Int32 raise OdsError {
  let raw = read_xsd_collapse(raw)
  let negative = raw.has_prefix("-")
  let digits = if negative || raw.has_prefix("+") {
    raw[1:].to_owned()
  } else {
    raw
  }
  if digits == "" {
    raise Invalid("empty nonnegative integer")
  }
  let mut n = 0
  for c in digits {
    let d = c.to_int() - 48
    if d < 0 || d > 9 || n > (max - d) / 10 {
      raise Invalid("nonnegative count exceeds budget or invalid lexical form")
    }
    n = n * 10 + d
    if n > max {
      raise Invalid("nonnegative count exceeds budget")
    }
  }
  if negative && n != 0 {
    raise Invalid("count must be nonnegative")
  }
  n
}
