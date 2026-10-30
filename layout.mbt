///|
// Decimal physical lengths are retained as validated tokens, not rounded pixels
// or approximate floating-point millimeters. 12 digits bound Int64 arithmetic.
fn physical_length(text : String) -> (String, Int64, Int64)? {
  let text = text.trim().to_owned()
  let (unit, mul, div) = if text.has_suffix("mm") {
    ("mm", 1L, 1L)
  } else if text.has_suffix("cm") {
    ("cm", 10L, 1L)
  } else if text.has_suffix("in") {
    ("in", 127L, 5L)
  } else if text.has_suffix("pt") {
    ("pt", 127L, 360L)
  } else if text.has_suffix("pc") {
    ("pc", 127L, 30L)
  } else {
    return None
  }
  let raw = text[:text.length() - unit.length()].to_owned()
  let mut num = 0L
  let mut scale = 1L
  let mut fraction = false
  let mut digits = 0
  for c in raw {
    if c == '.' && !fraction {
      fraction = true
      continue
    }
    if c < '0' || c > '9' || digits >= 12 {
      return None
    }
    num = num * 10L + (c.to_int() - 48).to_int64()
    if fraction {
      scale *= 10L
    }
    digits += 1
  }
  if digits == 0 {
    return None
  }
  let numerator = num * mul
  let denominator = scale * div
  if numerator <= 0L || numerator > 500L * denominator {
    return None
  }
  Some((text, numerator, denominator))
}

///|
/// Set an exact physical column length in mm/cm/in/pt/pc (0 < mm <= 500).
/// At most 12 decimal digits; no sign, exponent, percent or pixel lengths.
/// The validated token is retained; no DPI, rounding or visual-fit promise.
pub fn Sheet::set_column_width_length(
  self : Sheet,
  col : Int32,
  length : String,
) -> Unit raise OdsError {
  position(0, col)
  let (length, _, _) = match physical_length(length) {
    Some(v) => v
    None =>
      raise Invalid(
        "column length must be a bounded positive physical decimal (<=500mm)",
      )
  }
  let cols = if col + 1 > self.cols { col + 1 } else { self.cols }
  if self.rows * cols > 65536 {
    raise Invalid("sheet rendered grid exceeds 65536 cells")
  }
  self.precise_widths.set(col, length)
  match read_width_mm(length) {
    Some(mm) => self.widths.set(col, mm)
    None => self.widths.remove(col)
  }
  self.cols = cols
}

///|
/// Exact stored token, or integer-mm token for the legacy width API.
pub fn Sheet::column_width_length(self : Sheet, col : Int32) -> String? {
  match self.precise_widths.get(col) {
    Some(v) => Some(v)
    None =>
      match self.widths.get(col) {
        Some(mm) => Some("\{mm}mm")
        None => None
      }
  }
}

///|
/// Set a fixed physical row height. Automatic/content-fit heights are not modeled.
pub fn Sheet::set_row_height_length(
  self : Sheet,
  row : Int32,
  length : String,
) -> Unit raise OdsError {
  position(row, 0)
  let (length, _, _) = match physical_length(length) {
    Some(v) => v
    None =>
      raise Invalid(
        "row height must be a bounded positive physical decimal (<=500mm)",
      )
  }
  let rows = if row + 1 > self.rows { row + 1 } else { self.rows }
  if rows * self.cols > 65536 {
    raise Invalid("sheet rendered grid exceeds 65536 cells")
  }
  self.row_heights.set(row, length)
  self.rows = rows
}

///|
pub fn Sheet::row_height_length(self : Sheet, row : Int32) -> String? {
  self.row_heights.get(row)
}

///|
fn read_width_mm(text : String) -> Int32? {
  match physical_length(text) {
    Some((_, num, den)) =>
      if num % den == 0L && num / den >= 1L {
        Some((num / den).to_int())
      } else {
        None
      }
    None => None
  }
}
