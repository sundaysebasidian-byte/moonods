///|
priv struct CsvReader {
  rows : Array[Array[String]]
  mut fields : Array[String]
  mut field : StringBuilder
  mut field_units : Int32
  mut total_units : Int32
}

///|
fn CsvReader::character(self : CsvReader, c : Char) -> Unit raise OdsError {
  let units = if c.to_int() > 0xFFFF { 2 } else { 1 }
  self.field_units += units
  self.total_units += units
  if self.field_units > 32767 || self.total_units > 2097152 {
    raise Invalid("CSV text budget exceeded")
  }
  self.field.write_char(c)
}

///|
fn CsvReader::finish_field(self : CsvReader) -> Unit raise OdsError {
  if self.fields.length() >= 128 {
    raise Invalid("CSV exceeds 128 columns")
  }
  self.fields.push(self.field.to_string())
  self.field = StringBuilder()
  self.field_units = 0
}

///|
fn CsvReader::finish_row(self : CsvReader) -> Unit raise OdsError {
  self.finish_field()
  if self.rows.length() >= 1024 ||
    (self.rows.length() + 1) * self.fields.length() > 65536 {
    raise Invalid("CSV grid budget exceeded")
  }
  if !self.rows.is_empty() && self.fields.length() != self.rows[0].length() {
    raise Invalid("CSV rows must have equal column counts")
  }
  self.rows.push(self.fields)
  self.fields = []
}

///|
/// RFC4180 quoting with CRLF or LF record separators; bare CR is rejected.
/// Every field becomes Text (including empty fields and leading '='). No type
/// guessing or formula evaluation. Empty input imports one empty text cell.
/// Parsing/validation finishes before the workbook is mutated.
pub fn Workbook::add_csv_sheet(
  self : Workbook,
  name : String,
  text : String,
) -> Sheet raise OdsError {
  if text.length() > 4194304 {
    raise Invalid("CSV input exceeds 4194304 UTF-16 units")
  }
  let reader : CsvReader = {
    rows: [],
    fields: [],
    field: StringBuilder(),
    field_units: 0,
    total_units: 0,
  }
  let mut quoted = false
  let mut closed = false
  let mut cr = false
  let mut ended_row = false
  for c in text {
    if cr {
      if c != '\n' {
        raise Invalid("CSV bare CR record separator")
      }
      cr = false
      continue
    }
    if quoted {
      if c == '"' {
        quoted = false
        closed = true
      } else {
        reader.character(c)
      }
      continue
    }
    if closed && c == '"' {
      reader.character('"')
      quoted = true
      closed = false
      continue
    }
    if c == ',' {
      reader.finish_field()
      closed = false
      ended_row = false
    } else if c == '\r' || c == '\n' {
      reader.finish_row()
      closed = false
      cr = c == '\r'
      ended_row = true
    } else if c == '"' && !closed && reader.field_units == 0 {
      quoted = true
      ended_row = false
    } else {
      if closed || c == '"' {
        raise Invalid("CSV unexpected character around quote")
      }
      reader.character(c)
      ended_row = false
    }
  }
  if quoted || cr {
    raise Invalid("CSV truncated quote or CRLF")
  }
  if !ended_row {
    reader.finish_row()
  }
  // Validate XML-compatible strings and sheet budgets in an isolated sheet.
  let candidate = Workbook::new().add_sheet(name)
  for row, fields in reader.rows {
    candidate.set_row(row, 0, fields.map(s => Cell::new(Text(s))))
  }
  let sheet = self.add_sheet(name)
  for pos, cell in candidate.cells {
    sheet.cells[pos] = cell
  }
  sheet.rows = candidate.rows
  sheet.cols = candidate.cols
  sheet.text_units = candidate.text_units
  sheet
}

///|
fn csv_quote(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in text {
    if c == '"' {
      out.write_char('"')
    }
    out.write_char(c)
  }
  out.write_char('"')
  out.to_string()
}

///|
fn csv_formula_like(text : String) -> Bool {
  // Ignore leading whitespace as importers may trim it before type inference.
  for c in text {
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      continue
    }
    return c == '=' || c == '+' || c == '-' || c == '@'
  }
  false
}

///|
/// Deterministic comma CSV, quoted fields and CRLF records. Dates use ISO dates,
/// booleans true/false, numbers binary64 text. Empty and Text("") both emit "".
/// Merges are rejected. Formula caches require an explicit opt-in; formulas,
/// types, styles and sheet metadata cannot survive a CSV roundtrip.
/// External spreadsheet applications may infer types/formulas from CSV text.
/// use_formula_cache exports stored, possibly stale caches without recalculation.
/// reject_formula_like_text skips only leading ASCII space, TAB, CR and LF, then
/// rejects Text values starting =, +, - or @. It never changes data or rejects
/// typed negative numbers, and is a bounded policy rather than an application
/// sandbox. The default preserves the existing lossless text semantics.
pub fn Sheet::to_csv(
  self : Sheet,
  use_formula_cache~ : Bool = false,
  reject_formula_like_text~ : Bool = false,
) -> String raise OdsError {
  if !self.spans.is_empty() {
    raise Invalid("CSV export requires an unmerged sheet")
  }
  let out = XmlOutput::new()
  for row in 0..<self.rows {
    for col in 0..<self.cols {
      if col > 0 {
        out.write_string(",")
      }
      let value = match self.get(row, col) {
        Some(cell) => {
          if !use_formula_cache && cell.expression() is Some(_) {
            raise Invalid("CSV formula export requires use_formula_cache=true")
          }
          cell.value()
        }
        None => Empty
      }
      let text = match value {
        Empty => ""
        Text(s) => {
          if reject_formula_like_text && csv_formula_like(s) {
            raise Invalid("CSV formula-like text at row \{row} col \{col}")
          }
          s
        }
        Number(n) => finite_number_text(n)
        Boolean(b) => if b { "true" } else { "false" }
        Date(y, m, d) => "\{pad(y, 4)}-\{pad(m, 2)}-\{pad(d, 2)}"
      }
      out.write_string(csv_quote(text))
    }
    out.write_string("\r\n")
  }
  out.to_string()
}
