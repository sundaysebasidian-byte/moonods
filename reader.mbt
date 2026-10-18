///|
let read_office = "urn:oasis:names:tc:opendocument:xmlns:office:1.0#"

///|
let read_table = "urn:oasis:names:tc:opendocument:xmlns:table:1.0#"

///|
let read_text = "urn:oasis:names:tc:opendocument:xmlns:text:1.0#"

///|
/// Coordinates are zero-based. -1 means workbook/sheet scope.
pub(all) struct ImportDiagnostic {
  sheet : String
  row : Int32
  col : Int32
  code : String
  message : String
} derive(Eq, Debug)

///|
struct ImportResult {
  book : Workbook
  notices : Array[ImportDiagnostic]
}

///|
pub fn ImportResult::workbook(self : ImportResult) -> Workbook {
  self.book
}

///|
/// A copy: callers cannot mutate the reader's diagnostic record.
pub fn ImportResult::diagnostics(
  self : ImportResult,
) -> Array[ImportDiagnostic] {
  self.notices.copy()
}

///|
pub fn Workbook::sheet(self : Workbook, index : Int32) -> Sheet? {
  if index < 0 || index >= self.sheets.length() {
    None
  } else {
    Some(self.sheets[index])
  }
}

///|
pub fn Sheet::dimensions(self : Sheet) -> (Int32, Int32) {
  (self.rows, self.cols)
}

///|
pub fn Sheet::merge_span(
  self : Sheet,
  row : Int32,
  col : Int32,
) -> (Int32, Int32)? {
  self.spans.get((row, col))
}

///|
pub fn Sheet::is_covered(self : Sheet, row : Int32, col : Int32) -> Bool {
  self.covered.contains((row, col))
}

///|
fn ReadElement::elements(
  self : ReadElement,
) -> Array[ReadElement] raise OdsError {
  let result = []
  for part in self.parts {
    match part {
      ReadText(t) =>
        if t.trim() != "" {
          raise Invalid("unexpected XML character data")
        }
      ReadElement(e) => result.push(e)
    }
  }
  result
}

///|
fn ReadElement::attribute(
  self : ReadElement,
  ns : String,
  key : String,
) -> String? {
  self.attrs.get(ns + key)
}

///|
fn ReadElement::allowed(
  self : ReadElement,
  names : Array[String],
) -> Unit raise OdsError {
  for k, _ in self.attrs {
    if !names.contains(k) {
      raise Invalid("unsupported attribute: \{k}")
    }
  }
}

///|
fn read_positive(raw : String, max : Int32) -> Int32 raise OdsError {
  if raw == "" {
    raise Invalid("empty repeat/span count")
  }
  let mut n = 0
  for c in raw {
    let d = c.to_int() - 48
    if d < 0 || d > 9 || n > (max - d) / 10 {
      raise Invalid("repeat/span exceeds budget")
    }
    n = n * 10 + d
    if n > max {
      raise Invalid("repeat/span exceeds budget")
    }
  }
  if n < 1 {
    raise Invalid("repeat/span must be positive")
  }
  n
}

///|
fn ReadElement::count(
  self : ReadElement,
  ns : String,
  key : String,
  max : Int32,
) -> Int32 raise OdsError {
  match self.attribute(ns, key) {
    Some(s) => read_positive(s, max)
    None => 1
  }
}

///|
fn read_text_parts(node : ReadElement) -> String raise OdsError {
  let b = StringBuilder()
  let mut units = 0
  for part in node.parts {
    let s = match part {
      ReadText(t) => t
      ReadElement(e) =>
        if e.name == read_text + "s" {
          e.allowed([read_text + "c"])
          if !e.parts.is_empty() {
            raise Invalid("text:s must be empty")
          }
          let n = e.count(read_text, "c", 32767)
          let spaces = StringBuilder()
          for _ in 0..<n {
            spaces.write_char(' ')
          }
          spaces.to_string()
        } else if e.name == read_text + "tab" ||
          e.name == read_text + "line-break" {
          e.allowed([])
          if !e.parts.is_empty() {
            raise Invalid("text control must be empty")
          }
          if e.name == read_text + "tab" {
            "\t"
          } else {
            "\n"
          }
        } else {
          raise Invalid("unsupported rich text, hyperlink, or embedded object")
        }
    }
    units += s.length()
    if units > 32767 {
      raise Invalid("expanded cell text exceeds budget")
    }
    b.write_string(s)
  }
  b.to_string()
}

///|
fn read_cell_text(node : ReadElement) -> String raise OdsError {
  let b = StringBuilder()
  let mut first = true
  let mut units = 0
  for e in node.elements() {
    if e.name != read_text + "p" {
      raise Invalid("unsupported cell child: \{e.name}")
    }
    e.allowed([])
    if !first {
      b.write_char('\n')
      units += 1
    }
    first = false
    let s = read_text_parts(e)
    units += s.length()
    if units > 32767 {
      raise Invalid("expanded cell text exceeds budget")
    }
    b.write_string(s)
  }
  b.to_string()
}

///|
fn read_decimal_identity(raw : String) -> String raise OdsError {
  // Exact decimal normalization for already lexically validated finite inputs.
  // This compares source/output decimals; it does not claim decimal arithmetic.
  let digits : Array[Char] = []
  let mut negative = false
  let mut fractional = false
  let mut fraction_digits = 0
  let mut exponent = false
  let mut exponent_negative = false
  let mut power = 0
  for i, c in raw {
    if !exponent {
      if i == 0 && c == '-' {
        negative = true
      } else if c == '+' {
        ()
      } else if c == '.' {
        fractional = true
      } else if c == 'e' || c == 'E' {
        exponent = true
      } else {
        digits.push(c)
        if fractional {
          fraction_digits += 1
        }
      }
    } else if c == '-' {
      exponent_negative = true
    } else if c == '+' {
      ()
    } else {
      if power > 100000 {
        raise Invalid("numeric exponent outside supported decimal range")
      }
      power = power * 10 + c.to_int() - 48
    }
  }
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first += 1
  }
  if first == digits.length() {
    return if negative { "-0" } else { "0" }
  }
  let mut last = digits.length()
  while last > first && digits[last - 1] == '0' {
    last -= 1
  }
  let scale = (if exponent_negative { -power } else { power }) -
    fraction_digits +
    digits.length() -
    last
  let b = StringBuilder()
  if negative {
    b.write_char('-')
  }
  for i in first..<last {
    b.write_char(digits[i])
  }
  b.write_string("e\{scale}")
  b.to_string()
}

///|
fn read_finite_double(raw : String) -> Double raise OdsError {
  if raw.length() > 1024 {
    raise Invalid("numeric literal exceeds 1024 units")
  }
  // XML Schema decimal/exponent lexical subset; core parse_double also accepts
  // language-specific underscores, which must not be admitted as ODF numbers.
  let chars : Array[Char] = []
  for c in raw {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  if i < n && (chars[i] == '+' || chars[i] == '-') {
    i += 1
  }
  let mut digits = 0
  while i < n && chars[i] >= '0' && chars[i] <= '9' {
    i += 1
    digits += 1
  }
  if i < n && chars[i] == '.' {
    i += 1
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
      digits += 1
    }
  }
  if digits == 0 {
    raise Invalid("invalid ODF numeric lexical form")
  }
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    if i < n && (chars[i] == '+' || chars[i] == '-') {
      i += 1
    }
    let start = i
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    if start == i {
      raise Invalid("invalid ODF numeric exponent")
    }
  }
  if i != n {
    raise Invalid("invalid ODF numeric lexical form")
  }
  let result = @string.parse_double(raw[:]) catch {
    _ => raise Invalid("invalid numeric cell")
  }
  if result.is_nan() || result.is_inf() {
    raise Invalid("number must be finite")
  }
  if result == 0.0 {
    let mut mantissa = true
    for c in raw {
      if c == 'e' || c == 'E' {
        mantissa = false
      }
      if mantissa && c >= '1' && c <= '9' {
        raise Invalid("nonzero numeric input underflows to zero")
      }
    }
  }
  result
}

///|
fn read_value(node : ReadElement) -> Value raise OdsError {
  // Validate even display paragraphs on non-text values; never silently discard
  // annotations, drawings, links, or rich text embedded in numeric cells.
  let text = read_cell_text(node)
  let kind = node.attribute(read_office, "value-type")
  match
    node.attrs.get(
      "urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0#value-type",
    ) {
    Some(ext) =>
      if Some(ext) != kind {
        raise Invalid("unsupported or conflicting LibreOffice value type")
      }
    None => ()
  }
  let value = match kind {
    None => {
      if text != "" {
        raise Invalid("untyped nonempty cell")
      }
      Empty
    }
    Some("string") =>
      match node.attribute(read_office, "string-value") {
        Some(s) => {
          if text != "" && text != s {
            raise Invalid("string value/display conflict")
          }
          Text(s)
        }
        None => Text(text)
      }
    Some("float") => {
      let raw = node.attribute(read_office, "value").unwrap_or("")
      Number(read_finite_double(raw))
    }
    Some("boolean") =>
      match node.attribute(read_office, "boolean-value") {
        Some("true") | Some("1") => Boolean(true)
        Some("false") | Some("0") => Boolean(false)
        _ => raise Invalid("invalid boolean cell")
      }
    Some("date") => {
      let raw = node.attribute(read_office, "date-value").unwrap_or("")
      let p = raw.split("-").map(x => x.to_owned()).collect()
      if p.length() != 3 ||
        p[0].length() != 4 ||
        p[1].length() != 2 ||
        p[2].length() != 2 {
        raise Invalid("only Gregorian YYYY-MM-DD dates supported")
      }
      Date(
        read_positive(p[0], 9999),
        read_positive(p[1], 12),
        read_positive(p[2], 31),
      )
    }
    Some(other) => raise Invalid("unsupported ODF value type: \{other}")
  }
  // Reject conflicting alternate typed attributes instead of coercing them.
  for field in ["value", "boolean-value", "date-value", "string-value"] {
    if node.attribute(read_office, field) is Some(_) {
      let expected = match kind {
        Some("float") => "value"
        Some("boolean") => "boolean-value"
        Some("date") => "date-value"
        Some("string") => "string-value"
        _ => ""
      }
      if field != expected {
        raise Invalid("conflicting typed value attributes")
      }
    }
  }
  validate_value(value)
  value
}

///|
fn read_notice(
  notices : Array[ImportDiagnostic],
  diagnostic : ImportDiagnostic,
) -> Unit raise OdsError {
  if notices.length() >= 8192 {
    raise Invalid("import diagnostic budget exceeded")
  }
  notices.push(diagnostic)
}

///|
fn ReadElement::style_notice(
  self : ReadElement,
  notices : Array[ImportDiagnostic],
  sheet : String,
  row : Int32,
  col : Int32,
) -> Unit raise OdsError {
  if self.attribute(read_table, "style-name") is Some(_) ||
    self.attribute(read_table, "default-cell-style-name") is Some(_) {
    read_notice(notices, {
      sheet,
      row,
      col,
      code: "FORMATTING_DROPPED",
      message: "Source formatting is not retained by data-only import.",
    })
  }
}

///|
fn read_workbook_budget(book : Workbook) -> Unit raise OdsError {
  let mut grids = 0
  let mut units = 0
  for s in book.sheets {
    if s.rows * s.cols > 65536 {
      raise Invalid("sheet grid exceeds 65536 cells")
    }
    grids += s.rows * s.cols
    units += s.text_units
    if grids > 262144 || units > 4194304 {
      raise Invalid("workbook resource budget exceeded during import")
    }
  }
}

///|
fn import_table(
  node : ReadElement,
  book : Workbook,
  notices : Array[ImportDiagnostic],
) -> Unit raise OdsError {
  node.allowed([read_table + "name", read_table + "style-name"])
  let name = node.attribute(read_table, "name").unwrap_or("")
  let sheet = book.add_sheet(name)
  node.style_notice(notices, name, -1, -1)
  let mut row = 0
  let mut declared_cols = 0
  for child in node.elements() {
    if child.name == read_table + "table-column" {
      child.allowed([
        read_table + "style-name",
        read_table + "default-cell-style-name",
        read_table + "number-columns-repeated",
      ])
      if !child.parts.is_empty() || row != 0 {
        raise Invalid("unsupported table column placement/content")
      }
      let n = child.count(read_table, "number-columns-repeated", 128)
      if declared_cols > 128 - n {
        raise Invalid("column declaration exceeds limit")
      }
      child.style_notice(notices, name, -1, declared_cols)
      declared_cols += n
      sheet.cols = declared_cols
      read_workbook_budget(book)
      continue
    }
    if child.name != read_table + "table-row" {
      raise Invalid("unsupported table child: \{child.name}")
    }
    child.allowed([
      read_table + "number-rows-repeated",
      read_table + "style-name",
      read_table + "default-cell-style-name",
    ])
    let rows = child.count(read_table, "number-rows-repeated", 1024) catch {
      Invalid(msg) => raise Invalid("sheet '\{name}' row \{row} col 0: \{msg}")
    }
    if row > 1024 - rows {
      raise Invalid("row repeat exceeds grid")
    }
    if row + rows > sheet.rows {
      sheet.rows = row + rows
    }
    read_workbook_budget(book)
    let cells = child.elements()
    for r in row..<(row + rows) {
      child.style_notice(notices, name, r, -1)
      let mut col = 0
      for node in cells {
        let is_covered = node.name == read_table + "covered-table-cell"
        if !is_covered && node.name != read_table + "table-cell" {
          raise Invalid("unsupported row child")
        }
        let cols = node.count(read_table, "number-columns-repeated", 128) catch {
          Invalid(msg) =>
            raise Invalid("sheet '\{name}' row \{r} col \{col}: \{msg}")
        }
        if col > 128 - cols {
          raise Invalid("column repeat exceeds grid")
        }
        for c in col..<(col + cols) {
          try {
            if is_covered {
              node.allowed([read_table + "number-columns-repeated"])
              if !node.parts.is_empty() || !sheet.is_covered(r, c) {
                raise Invalid("unexpected/nonempty covered cell")
              }
            } else {
              node.allowed([
                read_table + "number-columns-repeated",
                read_table + "number-columns-spanned",
                read_table + "number-rows-spanned",
                read_table + "formula",
                read_table + "style-name",
                read_office + "value-type",
                read_office + "value",
                read_office + "boolean-value",
                read_office + "date-value",
                read_office + "string-value",
                "urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0#value-type",
              ])
              let value = read_value(node)
              match value {
                Number(n) => {
                  let raw = node.attribute(read_office, "value").unwrap_or("")
                  let stored = finite_number_text(n)
                  if read_decimal_identity(raw) != read_decimal_identity(stored) {
                    let preview = if raw.length() <= 96 {
                      raw
                    } else {
                      raw[:96].to_owned() + "…"
                    }
                    read_notice(notices, {
                      sheet: name,
                      row: r,
                      col: c,
                      code: "NUMBER_PRECISION_CHANGED",
                      message: "Source decimal \{preview} is stored as binary64 output \{stored}; exact decimal input is not retained.",
                    })
                  }
                }
                _ => ()
              }
              let cell = match node.attribute(read_table, "formula") {
                None => Cell::new(value)
                Some(f) => {
                  if node.ns.get("of") !=
                    Some("urn:oasis:names:tc:opendocument:xmlns:of:1.2") {
                    raise Invalid("formula namespace unsupported")
                  }
                  read_notice(notices, {
                    sheet: name,
                    row: r,
                    col: c,
                    code: "FORMULA_CACHE_NOT_RECALCULATED",
                    message: "Stored cache retained; edits do not recalculate this formula.",
                  })
                  Cell::formula(f, value)
                }
              }
              node.style_notice(notices, name, r, c)
              let cell = match value {
                Date(_, _, _) => cell.styled(DateISO)
                _ => cell
              }
              sheet.set(r, c, cell)
              read_workbook_budget(book)
              let nr = node.count(read_table, "number-rows-spanned", 1024)
              let nc = node.count(read_table, "number-columns-spanned", 128)
              if nr > 1 || nc > 1 {
                if rows != 1 || cols != 1 {
                  raise Invalid("repeated merged anchors unsupported")
                }
                sheet.merge(r, c, nr, nc)
                read_workbook_budget(book)
              }
            }
          } catch {
            Invalid(msg) =>
              raise Invalid("sheet '\{name}' row \{r} col \{c}: \{msg}")
          }
        }
        col += cols
      }
      // Missing covered positions must not be invented by the importer.
      for c in 0..<sheet.cols {
        if sheet.is_covered(r, c) && c >= col {
          raise Invalid("missing covered cell")
        }
      }
    }
    row += rows
  }
  if sheet.rows > row && !sheet.spans.is_empty() {
    raise Invalid("merge extends beyond input rows")
  }
}

///|
/// Import a bounded, data-only ODS subset. The explicit opt-in acknowledges
/// formatting, application metadata and view settings are not retained.
/// Unsupported semantic features fail, with sheet/cell context where known.
/// No partial workbook is returned on failure; formulas are never evaluated.
pub fn read_ods(
  data : Bytes,
  allow_formatting_loss~ : Bool = false,
) -> ImportResult raise OdsError {
  if !allow_formatting_loss {
    raise Invalid(
      "data-only import requires allow_formatting_loss=true; source formatting and metadata will not be retained",
    )
  }
  let omitted : Array[String] = []
  let result = import_content(read_ods_content_noticing(data, omitted))
  for path in omitted {
    read_notice(result.notices, {
      sheet: "",
      row: -1,
      col: -1,
      code: "PACKAGE_PART_DROPPED",
      message: "Source package part \{path} is not preserved by data-only import.",
    })
  }
  result
}

///|
fn import_content(xml : String) -> ImportResult raise OdsError {
  let root = read_xml(xml)
  if root.name != read_office + "document-content" {
    raise Invalid("expected ODF document-content namespace")
  }
  root.allowed([read_office + "version"])
  let book = Workbook::new()
  let notices : Array[ImportDiagnostic] = [
    {
      sheet: "",
      row: -1,
      col: -1,
      code: "DATA_ONLY_IMPORT",
      message: "Formatting, metadata, view settings, and numeric display text are not retained. Numbers use binary64; changed decimal representations are reported. Supported merges and formula text/cache are retained.",
    },
  ]
  let mut bodies = 0
  for child in root.elements() {
    if child.name == read_office + "automatic-styles" ||
      child.name == read_office + "font-face-decls" {
      if !child.elements().is_empty() || !child.attrs.is_empty() {
        read_notice(notices, {
          sheet: "",
          row: -1,
          col: -1,
          code: "DOCUMENT_FORMATTING_DROPPED",
          message: "Source \{child.name} is not retained by data-only import.",
        })
      }
      continue
    }
    if child.name == read_office + "scripts" {
      if !child.elements().is_empty() || !child.attrs.is_empty() {
        raise Invalid("scripts unsupported")
      }
      continue
    }
    if child.name != read_office + "body" {
      raise Invalid("unsupported document feature: \{child.name}")
    }
    bodies += 1
    if bodies != 1 {
      raise Invalid("duplicate office body")
    }
    child.allowed([])
    let contents = child.elements()
    if contents.length() != 1 || contents[0].name != read_office + "spreadsheet" {
      raise Invalid("expected one spreadsheet")
    }
    contents[0].allowed([])
    for table in contents[0].elements() {
      if table.name == read_table + "named-expressions" &&
        table.elements().is_empty() &&
        table.attrs.is_empty() {
        continue
      }
      if table.name != read_table + "table" {
        raise Invalid("unsupported spreadsheet feature: \{table.name}")
      }
      import_table(table, book, notices)
    }
  }
  if bodies != 1 || book.sheet_count() == 0 {
    raise Invalid("missing spreadsheet body or sheets")
  }
  // Reuse writer preflight to enforce aggregate grid/text budgets as well.
  book.content_xml() |> ignore
  { book, notices, }
}

///|
pub extend ImportDiagnostic with Eq::{equal, not_equal}

///|
pub extend ImportDiagnostic with @debug.Debug::{to_repr}
