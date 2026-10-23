///|
/// A snapshot of literal values or stored formula caches, with zero-based row.
/// Mapping does not evaluate formulas or fill merged cells.
pub(all) struct TableRecord {
  row : Int32
  values : Map[String, Value]
}

///|
/// Exact, case-sensitive header names. Every header must be a nonblank Text
/// literal and unique. Rejects merged sheets rather than guessing fill-down.
/// Includes blank data rows; absent cells map to Empty, Text("") stays distinct.
pub fn Sheet::records(
  self : Sheet,
  header_row~ : Int32 = 0,
) -> Array[TableRecord] raise OdsError {
  if header_row < 0 || header_row >= self.rows {
    raise Invalid("header row outside sheet")
  }
  if !self.spans.is_empty() {
    raise Invalid("record mapping requires an unmerged sheet")
  }
  let headers : Array[String] = []
  for col in 0..<self.cols {
    let name = match self.get(header_row, col) {
      Some(cell) => {
        if cell.expression() is Some(_) {
          raise Invalid("header must not be a formula")
        }
        match cell.value() {
          Text(s) if s.trim() != "" => s
          _ => raise Invalid("header must be nonblank text")
        }
      }
      None => raise Invalid("missing header")
    }
    if headers.contains(name) {
      raise Invalid("duplicate header: \{name}")
    }
    headers.push(name)
  }
  let result : Array[TableRecord] = []
  for row = header_row + 1; row < self.rows; row = row + 1 {
    let values : Map[String, Value] = Map([])
    for col, name in headers {
      values[name] = match self.get(row, col) {
        Some(cell) => cell.value()
        None => Empty
      }
    }
    result.push({ row, values, })
  }
  result
}
