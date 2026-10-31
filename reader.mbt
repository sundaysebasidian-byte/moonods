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
priv struct ReadNotices {
  items : Array[ImportDiagnostic]
  counts : Map[(String, String), Int32]
  summaries : Map[(String, String), (Int32, Int32, Int32)]
}

///|
fn ReadNotices::new() -> ReadNotices {
  { items: [], counts: {}, summaries: {}, }
}

///|
struct ImportResult {
  book : Workbook
  notices : ReadNotices
  xml_id_assignments : Array[XmlIdAssignment]
  xml_id_errors : Array[XmlIdDiagnostic]
  processor_events : Array[XmlProcessorEvent]
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
  self.notices.items.copy()
}

///|
pub fn ImportResult::xml_ids(self : ImportResult) -> Array[XmlIdAssignment] {
  self.xml_id_assignments.copy()
}

///|
pub fn ImportResult::xml_id_diagnostics(
  self : ImportResult,
) -> Array[XmlIdDiagnostic] {
  self.xml_id_errors.copy()
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
    if !names.contains(k) && k != xml_id_expanded_name {
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
    Some(s) => read_xsd_positive(s, max)
    None => 1
  }
}

///|
fn read_text_parts(node : ReadElement) -> String raise OdsError {
  let state : ReadParagraph = {
    output: StringBuilder(),
    units: 0,
    seen: false,
    pending_space: false,
  }
  state.append_parts(node)
  state.output.to_string()
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
    e.allowed([read_text + "style-name"])
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
// XML parsing already bounds depth (32), nodes (65536) and input size.
// Runs are flattened only after validation by read_cell_text/read_text_parts.
fn ReadElement::has_text_formatting(self : ReadElement) -> Bool {
  if self.name == read_text + "span" ||
    self.attribute(read_text, "style-name") is Some(_) {
    return true
  }
  for part in self.parts {
    if part is ReadElement(e) && e.has_text_formatting() {
      return true
    }
  }
  false
}

///|
fn read_decimal_identity(raw : String) -> String raise OdsError {
  let raw = read_xsd_collapse(raw)
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
  let raw = read_xsd_collapse(raw)
  if raw == "INF" || raw == "-INF" || raw == "NaN" {
    raise Invalid(
      "unsupported non-finite ODF numeric value; finite numbers required",
    )
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
fn read_value(node : ReadElement, extended : Bool) -> Value raise OdsError {
  // Validate even display paragraphs on non-text values; never silently discard
  // annotations, drawings, links, or unsupported text nodes in numeric cells.
  let text = read_cell_text(node)
  let kind = node.attribute(read_office, "value-type").map(read_xsd_collapse)
  match
    node.attrs.get(
      "urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0#value-type",
    ) {
    Some(ext) =>
      if Some(read_xsd_collapse(ext)) != kind {
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
        // ODF 1.3 Part 3 section 19.389: a supplied value attribute is
        // authoritative even when the validated display content differs.
        Some(s) => Text(s)
        None => Text(text)
      }
    Some("percentage") if extended =>
      Percentage(
        read_finite_double(node.attribute(read_office, "value").unwrap_or("")),
      )
    Some("currency") if extended => {
      let raw = node.attribute(read_office, "value").unwrap_or("")
      let amount = read_finite_double(raw)
      if read_decimal_identity(raw) !=
        read_decimal_identity(finite_number_text(amount)) {
        raise Invalid(
          "currency decimal cannot roundtrip through binary64 without changing its decimal value",
        )
      }
      Currency(amount, node.attribute(read_office, "currency").unwrap_or(""))
    }
    Some("time") if extended =>
      Duration(
        read_xsd_collapse(
          node.attribute(read_office, "time-value").unwrap_or(""),
        ),
      )
    Some("float") => {
      let raw = node.attribute(read_office, "value").unwrap_or("")
      Number(read_finite_double(raw))
    }
    Some("boolean") =>
      match
        node.attribute(read_office, "boolean-value").map(read_xsd_collapse) {
        Some("true") => Boolean(true)
        Some("false") => Boolean(false)
        _ => raise Invalid("invalid boolean cell")
      }
    Some("date") => {
      let raw = read_xsd_collapse(
        node.attribute(read_office, "date-value").unwrap_or(""),
      )
      if extended && raw.contains("T") {
        DateTime(raw)
      } else {
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
    }
    Some(other) => raise Invalid("unsupported ODF value type: \{other}")
  }
  // Reject conflicting alternate typed attributes instead of coercing them.
  for
    field in [
      "value", "boolean-value", "date-value", "string-value", "currency", "time-value",
    ] {
    if node.attribute(read_office, field) is Some(_) {
      let expected = match kind {
        Some("float") | Some("percentage") => "value"
        Some("currency") =>
          if field == "currency" {
            "currency"
          } else {
            "value"
          }
        Some("time") => "time-value"
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
  notices : ReadNotices,
  diagnostic : ImportDiagnostic,
) -> Unit raise OdsError {
  // Count every repeated loss. Keep the first 32 exact locations per sheet/code
  // and one explicit summary rather than rejecting an otherwise valid grid.
  // At most 32 sheets * 5 grouped codes * 33 entries, below the old hard cap.
  if [
      "FORMATTING_DROPPED", "RICH_TEXT_FORMATTING_DROPPED", "FORMULA_CACHE_NOT_RECALCULATED",
      "NUMBER_PRECISION_CHANGED", "STRING_DISPLAY_TEXT_DROPPED",
    ].contains(diagnostic.code) {
    let key = (diagnostic.sheet, diagnostic.code)
    let count = notices.counts.get(key).unwrap_or(0) + 1
    notices.counts.set(key, count)
    if count > 32 {
      let (index, first_row, first_col) = match notices.summaries.get(key) {
        Some(data) => data
        None => {
          if notices.items.length() >= 8192 {
            raise Invalid("import diagnostic budget exceeded")
          }
          let data = (notices.items.length(), diagnostic.row, diagnostic.col)
          notices.items.push(diagnostic)
          notices.summaries.set(key, data)
          data
        }
      }
      notices.items[index] = {
        sheet: diagnostic.sheet,
        row: -1,
        col: -1,
        code: diagnostic.code + "_SUMMARY",
        message: "\{count - 32} additional occurrences of \{diagnostic.code}; first additional row \{first_row} col \{first_col}, last row \{diagnostic.row} col \{diagnostic.col}. The first 32 occurrences retain exact details; all occurrences are counted, not silently truncated.",
      }
      return
    }
  }
  if notices.items.length() >= 8192 {
    raise Invalid("import diagnostic budget exceeded")
  }
  notices.items.push(diagnostic)
}

///|
fn read_preview(text : String) -> String {
  if text.length() <= 96 {
    text
  } else {
    text[:96].to_owned() + "…"
  }
}

///|
fn ReadElement::style_notice(
  self : ReadElement,
  notices : ReadNotices,
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
      message: "Source \{if self.name == read_table + "table-column" { "column style/width and default cell style" } else if self.name == read_table + "table-row" { "row style/height and default cell style" } else if self.name == read_table + "table" { "sheet style/view settings" } else { "cell style/number-format" }} is not retained by data-only import (style-name=\{read_preview(self.attribute(read_table, "style-name").unwrap_or(""))}, default-cell-style-name=\{read_preview(self.attribute(read_table, "default-cell-style-name").unwrap_or(""))}).",
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
// Recognize only physically empty suffix rows; no values, formulas, spans,
// covered cells, annotations or unknown attributes may be discarded.
fn read_empty_tail_row(node : ReadElement) -> (Int32, Int32)? raise OdsError {
  if node.name != read_table + "table-row" {
    return None
  }
  for key, _ in node.attrs {
    if ![
        read_table + "number-rows-repeated",
        read_table + "style-name",
        read_table + "default-cell-style-name",
      ].contains(key) {
      return None
    }
  }
  let mut cols = 0
  for cell in node.elements() {
    if cell.name != read_table + "table-cell" || !cell.parts.is_empty() {
      return None
    }
    for key, _ in cell.attrs {
      if ![read_table + "number-columns-repeated", read_table + "style-name"].contains(
          key,
        ) {
        return None
      }
    }
    let n = cell.count(read_table, "number-columns-repeated", 128)
    if cols > 128 - n {
      raise Invalid("column repeat exceeds grid")
    }
    cols += n
  }
  Some((node.count(read_table, "number-rows-repeated", 1048576), cols))
}

///|
fn read_table_children(
  node : ReadElement,
  notices : ReadNotices,
  sheet : String,
) -> Array[ReadElement] raise OdsError {
  let children = []
  for child in node.elements() {
    let expected = if [
        read_table + "table-header-rows",
        read_table + "table-rows",
      ].contains(child.name) {
      read_table + "table-row"
    } else if [
        read_table + "table-header-columns",
        read_table + "table-columns",
      ].contains(child.name) {
      read_table + "table-column"
    } else {
      ""
    }
    if expected == "" {
      children.push(child)
    } else {
      child.allowed([])
      let contents = child.elements()
      if contents.is_empty() {
        raise Invalid("empty table row/column container")
      }
      for content in contents {
        if content.name != expected {
          raise Invalid("unsupported table row/column container child")
        }
        children.push(content)
      }
      if child.name == read_table + "table-header-rows" ||
        child.name == read_table + "table-header-columns" {
        read_notice(notices, {
          sheet,
          row: -1,
          col: -1,
          code: "TABLE_HEADER_METADATA_DROPPED",
          message: "Source \{child.name} cells retain their positions and typed data; print/repeated-header metadata is not retained.",
        })
      }
    }
  }
  children
}

///|
fn import_table(
  node : ReadElement,
  book : Workbook,
  notices : ReadNotices,
  extended : Bool,
  formatting : ReadFormatting?,
) -> Unit raise OdsError {
  node.allowed([read_table + "name", read_table + "style-name"])
  let name = node.attribute(read_table, "name").unwrap_or("")
  let sheet = book.add_sheet(name)
  node.style_notice(notices, name, -1, -1)
  let mut row = 0
  let mut declared_cols = 0
  let column_defaults : Map[Int32, String] = Map([])
  let children = read_table_children(node, notices, name)
  let mut tail_start = children.length()
  let mut tail_rows = 0
  let mut tail_cols = 0
  while tail_start > 0 {
    // Invalid suffixes use the normal parser so contextual errors are preserved.
    let empty = read_empty_tail_row(children[tail_start - 1]) catch {
      Invalid(_) => None
    }
    match empty {
      None => break
      Some((n, cols)) => {
        tail_cols = if cols > tail_cols { cols } else { tail_cols }
        if tail_rows > 1048576 - n {
          raise Invalid("empty tail exceeds row extent")
        }
        tail_rows += n
        tail_start -= 1
      }
    }
  }
  // Preserve ordinary in-budget empty rows. Large suffixes are never expanded.
  let mut trim_tail = false
  for index, child in children {
    if index == tail_start {
      if row > 1048576 - tail_rows {
        raise Invalid("empty tail exceeds row extent")
      }
      let total_rows = row + tail_rows
      let total_cols = if sheet.cols > tail_cols {
        sheet.cols
      } else {
        tail_cols
      }
      let mut other_grids = 0
      for s in book.sheets {
        if s.name != name {
          other_grids += s.rows * s.cols
        }
      }
      // Omit the whole physically empty suffix only if preserving it would
      // exceed the remaining row, sheet-grid or workbook-grid budget.
      trim_tail = total_rows > 1024 ||
        total_rows * total_cols > 65536 ||
        other_grids + total_rows * total_cols > 262144
      if trim_tail {
        if sheet.rows > row && !sheet.spans.is_empty() {
          raise Invalid("merge crosses omitted empty tail boundary")
        }
        break
      }
    }
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
      let width = match formatting {
        Some(format) =>
          format.column_width(child.attribute(read_table, "style-name"))
        None => None
      }
      for c in declared_cols..<(declared_cols + n) {
        if child.attribute(read_table, "default-cell-style-name") is Some(style) {
          column_defaults.set(c, style)
        }
        if width is Some(mm) {
          sheet.set_column_width_length(c, mm)
          if formatting is Some(format) {
            format.retained_widths += 1
          }
        }
      }
      if width is Some(_) {
        read_notice(notices, {
          sheet: name,
          row: -1,
          col: declared_cols,
          code: "FORMATTING_DROPPED",
          message: "Exact physical column width retained; source column style names, default references and other metadata are normalized, not copied verbatim.",
        })
      } else {
        child.style_notice(notices, name, -1, declared_cols)
      }
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
    let height = match formatting {
      Some(format) =>
        format.row_height(child.attribute(read_table, "style-name"))
      None => None
    }
    for r in row..<(row + rows) {
      if height is Some(length) {
        sheet.set_row_height_length(r, length)
        if formatting is Some(format) {
          format.retained_heights += 1
        }
        read_notice(notices, {
          sheet: name,
          row: r,
          col: -1,
          code: "ROW_HEIGHT_RETAINED",
          message: "Fixed physical row height retained; row style identity and other metadata are not copied verbatim.",
        })
      } else {
        child.style_notice(notices, name, r, -1)
      }
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
              node.allowed([
                read_table + "number-columns-repeated",
                read_table + "style-name",
              ])
              if !node.parts.is_empty() || !sheet.is_covered(r, c) {
                raise Invalid("unexpected/nonempty covered cell")
              }
              node.style_notice(notices, name, r, c)
            } else {
              let allowed_attributes = [
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
              ]
              if extended {
                allowed_attributes.push(read_office + "currency")
                allowed_attributes.push(read_office + "time-value")
              }
              node.allowed(allowed_attributes)
              let value = read_value(node, extended)
              if node.attribute(read_office, "string-value") is Some(stored) &&
                value is Text(_) &&
                node.parts
                .iter()
                .any(part => {
                  match part {
                    ReadElement(child) => child.name == read_text + "p"
                    _ => false
                  }
                }) &&
                read_cell_text(node) != stored {
                read_notice(notices, {
                  sheet: name,
                  row: r,
                  col: c,
                  code: "STRING_DISPLAY_TEXT_DROPPED",
                  message: "Explicit office:string-value is retained as the cell value; distinct source display text is not retained by this data model.",
                })
              }
              if node.has_text_formatting() {
                read_notice(notices, {
                  sheet: name,
                  row: r,
                  col: c,
                  code: "RICH_TEXT_FORMATTING_DROPPED",
                  message: "Supported text spans/paragraph styles are flattened; text whitespace and typed values are retained, run styling and numeric display text are not.",
                })
              }
              match value {
                Number(n) | Percentage(n) | Currency(n, _) => {
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
                  let normalized = read_formula_prefix(f, node.ns)
                  read_notice(notices, {
                    sheet: name,
                    row: r,
                    col: c,
                    code: "FORMULA_CACHE_NOT_RECALCULATED",
                    message: "Stored cache retained; edits do not recalculate this formula.",
                  })
                  Cell::formula(normalized, value)
                }
              }
              let selected_style = match
                node.attribute(read_table, "style-name") {
                Some(style) => Some(style)
                None =>
                  match child.attribute(read_table, "default-cell-style-name") {
                    Some(style) => Some(style)
                    None => column_defaults.get(c)
                  }
              }
              let normalized_style = match formatting {
                Some(format) => format.cell_style(selected_style, value~)
                None => None
              }
              if normalized_style is None {
                if formatting is Some(format) &&
                  (
                    selected_style is Some(_) ||
                    format.source.defaults.contains("table-cell")
                  ) {
                  read_notice(notices, {
                    sheet: name,
                    row: r,
                    col: c,
                    code: "FORMATTING_DROPPED",
                    message: "Effective cell formatting is outside the supported presets after resolving defaults/inheritance (source=\{read_preview(selected_style.unwrap_or("family default"))}); typed value retained, formatting dropped. No style-name guessing is used.",
                  })
                } else {
                  node.style_notice(notices, name, r, c)
                }
              }
              let cell = match normalized_style {
                Some(style) => {
                  if formatting is Some(format) {
                    format.retained_cells += 1
                  }
                  cell.styled(style)
                }
                None =>
                  match value {
                    Date(_, _, _) => cell.styled(DateISO)
                    _ => cell
                  }
              }
              sheet.set(r, c, cell)
              read_workbook_budget(book)
              let nr = node.count(read_table, "number-rows-spanned", 1024)
              let nc = node.count(read_table, "number-columns-spanned", 128)
              if nr > 1 || nc > 1 {
                // ODF 1.3 section 19.681 permits repeated rows with only
                // horizontal merges. Section 19.679.3 forbids repeating a
                // merged cell across columns, even for vertical-only spans.
                if cols != 1 || (rows != 1 && nr != 1) {
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
  if formatting is Some(format) {
    for c in declared_cols..<sheet.cols {
      if format.column_width(None) is Some(mm) {
        sheet.set_column_width_length(c, mm)
        format.retained_widths += 1
      }
    }
  }
  if trim_tail {
    if row > 1048576 - tail_rows {
      raise Invalid("empty tail exceeds row extent")
    }
    read_notice(notices, {
      sheet: name,
      row,
      col: -1,
      code: "EMPTY_TAIL_ROWS_DROPPED",
      message: "Data-only import omits \{tail_rows} trailing empty rows and their row/cell formatting; source extent is not retained.",
    })
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
  allow_extended_types~ : Bool = false,
  preserve_basic_formatting~ : Bool = false,
) -> ImportResult raise OdsError {
  if !allow_formatting_loss {
    raise Invalid(
      "data-only import requires allow_formatting_loss=true; source formatting and metadata will not be retained",
    )
  }
  let omitted : Array[String] = []
  let styles : Array[String] = []
  let package_ids : Array[XmlIdAssignment] = []
  let package_id_errors : Array[XmlIdDiagnostic] = []
  let package_events : Array[XmlProcessorEvent] = []
  let xml = read_ods_content_noticing(
    data,
    omitted,
    require_manifest=true,
    id_assignments=package_ids,
    id_diagnostics=package_id_errors,
    processor_events=package_events,
    style_parts=if preserve_basic_formatting { Some(styles) } else { None },
  )
  let result = import_content(
    xml,
    allow_extended_types~,
    preserve_basic_formatting~,
    styles~,
  )
  for event in package_events {
    result.processor_events.push(event)
  }
  for id in package_ids {
    result.xml_id_assignments.push(id)
  }
  for error in package_id_errors {
    result.xml_id_errors.push(error)
  }
  for event in result.processor_events {
    if event.kind == "MANIFEST_EXTENSION_NOT_INTERPRETED" {
      read_notice(result.notices, {
        sheet: "",
        row: -1,
        col: -1,
        code: "PACKAGE_EXTENSION_DROPPED",
        message: "Foreign manifest extension not interpreted or preserved: " +
        event.name,
      })
    }
  }
  for path in omitted {
    if path.has_prefix("META-INF/") && path.contains("signatures") {
      read_notice(result.notices, {
        sheet: "",
        row: -1,
        col: -1,
        code: "SIGNATURE_NOT_VERIFIED",
        message: "Signature XML parsed, but cryptographic validity not checked; signature omitted on data-only export: " +
        path,
      })
    }
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
fn import_content(
  xml : String,
  allow_extended_types~ : Bool = false,
  preserve_basic_formatting~ : Bool = false,
  styles~ : Array[String] = [],
) -> ImportResult raise OdsError {
  let xml_id_assignments : Array[XmlIdAssignment] = []
  let xml_id_errors : Array[XmlIdDiagnostic] = []
  let processor_events : Array[XmlProcessorEvent] = []
  let root = read_xml(
    xml,
    document_part="content.xml",
    id_assignments=xml_id_assignments,
    id_diagnostics=xml_id_errors,
    processor_events~,
  )
  if root.name != read_office + "document-content" {
    raise Invalid("expected ODF document-content namespace")
  }
  root.allowed([read_office + "version"])
  let book = Workbook::new()
  let notices = ReadNotices::new()
  let formatting = if preserve_basic_formatting {
    Some(read_formatting(root, styles))
  } else {
    None
  }
  read_notice(notices, {
    sheet: "",
    row: -1,
    col: -1,
    code: "DATA_ONLY_IMPORT",
    message: if preserve_basic_formatting {
      "Only recognized preset styles, exact physical column lengths and fixed row heights may be retained; other formatting, metadata, view settings and display text are not retained. Values, merges and formula/cache follow the selected type policy. BASIC_FORMATTING_SUBSET reports actual retained counts; repeated losses retain 32 exact occurrences plus counted summaries."
    } else {
      "Formatting, metadata, view settings, and numeric display text are not retained. Numbers use binary64; changed decimal representations are reported. Supported merges and formula text/cache are retained. Repeated per-sheet loss diagnostics retain 32 exact occurrences and an explicit counted summary."
    },
  })
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
          message: "Source \{child.name} is not retained in full; only an explicitly enabled basic formatting subset may be normalized.",
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
      import_table(table, book, notices, allow_extended_types, formatting)
    }
  }
  if bodies != 1 || book.sheet_count() == 0 {
    raise Invalid("missing spreadsheet body or sheets")
  }
  if formatting is Some(format) {
    read_notice(notices, {
      sheet: "",
      row: -1,
      col: -1,
      code: "BASIC_FORMATTING_SUBSET",
      message: "Retained \{format.retained_cells} normalized preset cell styles and \{format.retained_widths} exact physical column widths and \{format.retained_heights} fixed row heights. Other definitions, names, fonts, automatic sizing, layout, themes and metadata are not retained; arbitrary style XML is never copied.",
    })
  }
  // Reuse writer preflight to enforce aggregate grid/text budgets as well.
  book.content_xml() |> ignore
  { book, notices, xml_id_assignments, xml_id_errors, processor_events, }
}

///|
pub extend ImportDiagnostic with Eq::{equal, not_equal}

///|
pub extend ImportDiagnostic with @debug.Debug::{to_repr}

///|
// Normalize only the outer OpenFormula namespace prefix. The body is opaque;
// extension-function prefix semantics and formula correctness are not validated.
fn read_formula_prefix(
  f : String,
  ns : Map[String, String],
) -> String raise OdsError {
  let prefix = StringBuilder()
  let mut first = true
  for c in f {
    if c == ':' {
      break
    }
    if !(if first { xml_name_start(c) } else { xml_name_char(c) }) {
      raise Invalid("unsupported formula namespace prefix")
    }
    prefix.write_char(c)
    first = false
  }
  let name = prefix.to_string()
  if first || !f.has_prefix(name + ":=") || f.length() <= name.length() + 2 {
    raise Invalid("formula requires namespace prefix and nonempty body")
  }
  if ns.get(name) != Some("urn:oasis:names:tc:opendocument:xmlns:of:1.2") {
    raise Invalid("formula namespace unsupported")
  }
  "of:" + f[name.length() + 1:].to_owned()
}

///|
pub fn ImportResult::xml_events(
  self : ImportResult,
) -> Array[XmlProcessorEvent] {
  self.processor_events.copy()
}
