///|
/// Small interoperable style vocabulary; arbitrary properties are outside MVP.
pub(all) enum Style {
  Plain
  Header
  Highlight
  Decimal2
  DateISO
}

///|
pub fn Cell::styled(self : Cell, style : Style) -> Cell {
  { value: self.value, formula: self.formula, style, }
}

///|
fn Style::id(self : Style) -> String {
  match self {
    Plain => "Plain"
    Header => "Header"
    Highlight => "Highlight"
    Decimal2 => "Decimal2"
    DateISO => "DateISO"
  }
}

///|
fn preset_styles() -> String {
  "<number:number-style style:name=\"N2\"><number:number number:decimal-places=\"2\" number:min-integer-digits=\"1\"/></number:number-style><number:date-style style:name=\"DISO\"><number:year number:style=\"long\"/><number:text>-</number:text><number:month number:style=\"long\"/><number:text>-</number:text><number:day number:style=\"long\"/></number:date-style><style:style style:name=\"Plain\" style:family=\"table-cell\"><style:table-cell-properties fo:wrap-option=\"wrap\"/></style:style><style:style style:name=\"Header\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#17324D\" fo:wrap-option=\"wrap\"/><style:text-properties fo:font-weight=\"bold\" style:font-weight-asian=\"bold\" style:font-weight-complex=\"bold\" fo:color=\"#FFFFFF\"/></style:style><style:style style:name=\"Highlight\" style:family=\"table-cell\"><style:table-cell-properties fo:background-color=\"#FFF2CC\" fo:wrap-option=\"wrap\"/></style:style><style:style style:name=\"Decimal2\" style:family=\"table-cell\" style:data-style-name=\"N2\"><style:paragraph-properties fo:text-align=\"end\"/></style:style><style:style style:name=\"DateISO\" style:family=\"table-cell\" style:data-style-name=\"DISO\"/>"
}

///|
/// Emit the requested ODF fixed column length in integer millimeters (1..500).
/// Viewer rounding, font metrics, zoom and physical print layout are not
/// guaranteed. No app-specific pixel/point compensation is applied.
pub fn Sheet::set_column_width(
  self : Sheet,
  col : Int,
  mm : Int,
) -> Unit raise OdsError {
  position(0, col)
  if mm < 1 || mm > 500 {
    raise Invalid("column width must be 1..500 mm")
  }
  let cols = if col + 1 > self.cols { col + 1 } else { self.cols }
  if self.rows * cols > 65536 {
    raise Invalid("sheet rendered grid exceeds 65536 cells")
  }
  self.widths.set(col, mm)
  self.cols = cols
}

///|
fn Workbook::column_styles(self : Workbook) -> String {
  let used : Map[Int, Bool] = Map([])
  for s in self.sheets {
    for _, mm in s.widths {
      used.set(mm, true)
    }
  }
  let b = StringBuilder()
  for mm in 1..<=500 {
    if used.contains(mm) {
      b.write_string(
        "<style:style style:name=\"W\{mm}\" style:family=\"table-column\"><style:table-column-properties style:column-width=\"\{mm}mm\"/></style:style>",
      )
    }
  }
  b.to_string()
}

///|
/// Merge a zero-based rectangle. Covered values are never silently discarded.
pub fn Sheet::merge(
  self : Sheet,
  row : Int,
  col : Int,
  rows : Int,
  cols : Int,
) -> Unit raise OdsError {
  position(row, col)
  if rows < 1 || rows > 1024 || cols < 1 || cols > 128 || rows * cols == 1 {
    raise Invalid("merge must cover at least two cells within grid bounds")
  }
  position(row + rows - 1, col + cols - 1)
  if self.spans.length() >= 256 {
    raise Invalid("sheet exceeds 256 merges")
  }
  let nr = if row + rows > self.rows { row + rows } else { self.rows }
  let nc = if col + cols > self.cols { col + cols } else { self.cols }
  if nr * nc > 65536 {
    raise Invalid("sheet rendered grid exceeds 65536 cells")
  }
  for r in row..<(row + rows) {
    for c in col..<(col + cols) {
      if self.covered.contains((r, c)) || self.spans.contains((r, c)) {
        raise Invalid("overlapping merges")
      }
      if (r != row || c != col) && self.cells.contains((r, c)) {
        raise Invalid("merge would discard an existing cell")
      }
    }
  }
  for r in row..<(row + rows) {
    for c in col..<(col + cols) {
      if r != row || c != col {
        self.covered.set((r, c), true)
      }
    }
  }
  self.spans.set((row, col), (rows, cols))
  self.rows = nr
  self.cols = nc
}
