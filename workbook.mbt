///|
struct Sheet {
  name : String
  cells : Map[(Int32, Int32), Cell]
  mut rows : Int32
  mut cols : Int32
  mut text_units : Int32
  widths : Map[Int32, Int32]
  precise_widths : Map[Int32, String]
  row_heights : Map[Int32, String]
  spans : Map[(Int32, Int32), (Int32, Int32)]
  covered : Map[(Int32, Int32), Bool]
}

///|
struct Workbook {
  sheets : Array[Sheet]
}

///|
pub fn Workbook::new() -> Workbook {
  { sheets: [], }
}

///|
pub fn Workbook::add_sheet(
  self : Workbook,
  name : String,
) -> Sheet raise OdsError {
  validate_name(name)
  if self.sheets.length() >= 32 {
    raise Invalid("workbook exceeds 32 sheets")
  }
  for s in self.sheets {
    if s.name.to_lower() == name.to_lower() {
      raise Invalid("duplicate sheet name")
    }
  }
  let s = {
    name,
    cells: {},
    rows: 1,
    cols: 1,
    text_units: 0,
    widths: {},
    precise_widths: {},
    row_heights: {},
    spans: {},
    covered: {},
  }
  self.sheets.push(s)
  s
}

///|
pub fn Sheet::name(self : Sheet) -> String {
  self.name
}

///|
pub fn Workbook::sheet_count(self : Workbook) -> Int32 {
  self.sheets.length()
}

///|
pub fn Sheet::get(self : Sheet, row : Int32, col : Int32) -> Cell? {
  self.cells.get((row, col))
}

///|
fn validate_name(s : String) -> Unit raise OdsError {
  validate_text(s)
  if s.length() == 0 ||
    s.length() > 31 ||
    s.trim() == "" ||
    s.has_prefix("'") ||
    s.has_suffix("'") {
    raise Invalid(
      "sheet name must have 1..31 units, nonblank, without boundary apostrophes",
    )
  }
  for c in s {
    if "[]:*?/\\".contains(c.to_string()) || c.to_int() < 32 {
      raise Invalid("invalid interoperable sheet name")
    }
  }
}

///|
fn position(row : Int32, col : Int32) -> Unit raise OdsError {
  if row < 0 || col < 0 || row >= 1024 || col >= 128 {
    raise Invalid("cell index exceeds 1024 rows or 128 columns")
  }
}

///|
fn Cell::units(self : Cell) -> Int32 {
  let n = match self.value {
    Text(s) | Duration(s) | DateTime(s) => s.length()
    Currency(_, code) => code.length()
    _ => 0
  }
  n +
  (match self.formula {
    Some(f) => f.length()
    None => 0
  })
}

///|
/// Zero-based coordinate. Validation precedes mutation.
pub fn Sheet::set(
  self : Sheet,
  row : Int32,
  col : Int32,
  cell : Cell,
) -> Unit raise OdsError {
  self.set_row(row, col, [cell])
}

///|
/// Write a contiguous row atomically. All cells are validated before mutation,
/// including merge coverage and the net text budget after replacements. An
/// empty array is a no-op at a valid coordinate and does not grow the grid.
pub fn Sheet::set_row(
  self : Sheet,
  row : Int32,
  start_col : Int32,
  cells : Array[Cell],
) -> Unit raise OdsError {
  position(row, start_col)
  if cells.length() > 128 - start_col {
    raise Invalid("row write exceeds 128 columns")
  }
  if cells.is_empty() {
    return
  }
  let rows = if row + 1 > self.rows { row + 1 } else { self.rows }
  let end_col = start_col + cells.length()
  let cols = if end_col > self.cols { end_col } else { self.cols }
  if rows * cols > 65536 {
    raise Invalid("sheet rendered grid exceeds 65536 cells")
  }
  let mut units = self.text_units
  for i, cell in cells {
    let col = start_col + i
    if self.covered.contains((row, col)) {
      raise Invalid("cannot write covered merge cell")
    }
    let old = match self.cells.get((row, col)) {
      Some(c) => c.units()
      None => 0
    }
    units = units - old + cell.units()
  }
  if units > 2097152 {
    raise Invalid("sheet text exceeds 2097152 UTF-16 units")
  }
  for i, cell in cells {
    self.cells.set((row, start_col + i), cell)
  }
  self.rows = rows
  self.cols = cols
  self.text_units = units
}

///|
let namespaces : String = " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\""

///|
/// Inspectable XML for diagnostics. ODS output is provided by to_ods().
pub fn Workbook::content_xml(self : Workbook) -> String raise OdsError {
  if self.sheets.is_empty() {
    raise Invalid("workbook needs at least one sheet")
  }
  let mut grid = 0
  let mut units = 0
  for s in self.sheets {
    grid += s.rows * s.cols
    units += s.text_units
    if grid > 262144 || units > 4194304 {
      raise Invalid("workbook resource budget exceeded")
    }
  }
  // Preflight workbook totals before allocating serialized XML. Escaping can
  // expand text, so a second byte budget is enforced at every append.
  let b = XmlOutput::new()
  b.write_string(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content\{namespaces} office:version=\"1.3\"><office:automatic-styles>\{self.column_styles()}</office:automatic-styles><office:body><office:spreadsheet>",
  )
  for sheet_index, s in self.sheets {
    b.write_string("<table:table table:name=\"\{xml_escape(s.name)}\">")
    for col in 0..<s.cols {
      let a = if s.precise_widths.contains(col) {
        " table:style-name=\"CW\{sheet_index}_\{col}\""
      } else {
        match s.widths.get(col) {
          Some(mm) => " table:style-name=\"W\{mm}\""
          None => ""
        }
      }
      b.write_string("<table:table-column\{a}/>")
    }
    for row in 0..<s.rows {
      let row_style = if s.row_heights.contains(row) {
        " table:style-name=\"RH\{sheet_index}_\{row}\""
      } else {
        ""
      }
      b.write_string("<table:table-row\{row_style}>")
      let mut col = 0
      while col < s.cols {
        let mut count = 1
        if s.covered.contains((row, col)) {
          while col + count < s.cols && s.covered.contains((row, col + count)) {
            count += 1
          }
          if count == 1 {
            b.write_string("<table:covered-table-cell/>")
          } else {
            b.write_string(
              "<table:covered-table-cell table:number-columns-repeated=\"\{count}\"/>",
            )
          }
        } else {
          let cell = s.cells
            .get((row, col))
            .unwrap_or({ value: Empty, formula: None, style: Plain, })
          let extra = match s.spans.get((row, col)) {
            Some((nr, nc)) =>
              " table:number-rows-spanned=\"\{nr}\" table:number-columns-spanned=\"\{nc}\""
            None => {
              let identity = cell.xml("")
              // Do not coalesce formula cells: relative-reference behavior in
              // office applications is not established by the stored cache.
              while cell.formula is None &&
                    col + count < s.cols &&
                    !s.covered.contains((row, col + count)) &&
                    !s.spans.contains((row, col + count)) {
                let next = s.cells
                  .get((row, col + count))
                  .unwrap_or({ value: Empty, formula: None, style: Plain, })
                if next.xml("") != identity {
                  break
                }
                count += 1
              }
              if count > 1 {
                " table:number-columns-repeated=\"\{count}\""
              } else {
                ""
              }
            }
          }
          b.write_string(cell.xml(extra))
        }
        col += count
      }
      b.write_string("</table:table-row>")
    }
    b.write_string("</table:table>")
  }
  b.write_string(
    "</office:spreadsheet></office:body></office:document-content>",
  )
  b.to_string()
}
