// Read / inspect / edit / convert an external .ods through the public API.
// JS target only: the file adapters below use Node. The reader itself is pure
// MoonBit. Configuration is by environment variables (no fake UI):
//   ODS_INPUT          required, path of the .ods to read
//   ODS_ACCEPT_LOSS=1  opt in to lossy import (formatting etc. is dropped);
//                      without it any item that would be lost is a refusal
//   ODS_CSV            optional, write sheet 0 as CSV (display of values only)
//   ODS_SET            optional edit "sheet,row,col,number"
//   ODS_OUTPUT         optional, write the (edited) workbook back as .ods
// Exit code 0 = accepted, 1 = refused or failed ("ERROR: ..." on stdout).

///|
extern "js" fn env(name : String) -> String =
  #| (n) => process.env[n] || ''

///|
extern "js" fn read_file(path : String) -> Bytes =
  #| (p) => new Uint8Array(require('node:fs').readFileSync(p))

///|
extern "js" fn write_file(path : String, data : Bytes) -> Unit =
  #| (p, d) => require('node:fs').writeFileSync(p, d)

///|
extern "js" fn parse_number(s : String) -> Double =
  #| (s) => (s.trim() === '' ? NaN : Number(s))

///|
extern "js" fn write_text(path : String, data : String) -> Unit =
  #| (p, d) => require('node:fs').writeFileSync(p, d)

///|
extern "js" fn exit_with(code : Int32) -> Unit =
  #| (c) => process.exit(c)

///|
suberror UsageError {
  Usage(String)
}

///|
fn show(v : @ods.Value) -> String {
  match v {
    Empty => "(empty)"
    Text(s) => "text:\{s}"
    Number(d) => "number:\{d}"
    Boolean(b) => "bool:\{b}"
    Date(y, m, d) => "date:\{y}-\{pad2(m)}-\{pad2(d)}"
  }
}

///|
fn pad2(n : Int32) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
fn csv_field(v : @ods.Value) -> String {
  let s = match v {
    Empty => ""
    Text(s) => s
    Number(d) => d.to_string()
    Boolean(b) => b.to_string()
    Date(y, m, d) => "\{y}-\{pad2(m)}-\{pad2(d)}"
  }
  if s.contains(",") || s.contains("\"") || s.contains("\n") {
    "\"" + s.replace_all(old="\"", new="\"\"") + "\""
  } else {
    s
  }
}

///|
fn run() -> Unit raise {
  let input = env("ODS_INPUT")
  if input == "" {
    raise Usage("set ODS_INPUT to an .ods path")
  }
  let loss = env("ODS_ACCEPT_LOSS") == "1"
  let imported = @ods.read_ods(read_file(input), allow_formatting_loss=loss)
  let book = imported.workbook()
  println("accepted: \{input} (accept_loss=\{loss})")
  for i = 0; i < book.sheet_count(); i = i + 1 {
    let sheet = book.sheet(i).unwrap()
    let (rows, cols) = sheet.dimensions()
    println("sheet[\{i}] \{sheet.name()}  \{rows} rows x \{cols} cols")
    for r = 0; r < rows; r = r + 1 {
      for c = 0; c < cols; c = c + 1 {
        match sheet.get(r, c) {
          None => ()
          Some(cell) =>
            if cell.value() != Empty || cell.expression() is Some(_) {
              let f = match cell.expression() {
                Some(e) => "  formula=\{e} (cached value, not recalculated)"
                None => ""
              }
              println("  (\{r},\{c}) \{show(cell.value())}\{f}")
            }
        }
      }
    }
  }
  println("diagnostics: \{imported.diagnostics().length()}")
  for d in imported.diagnostics() {
    println(
      "  \{d.code} sheet=\{d.sheet} row=\{d.row} col=\{d.col}: \{d.message}",
    )
  }
  let csv = env("ODS_CSV")
  if csv != "" {
    let sheet = book.sheet(0).unwrap()
    let (rows, cols) = sheet.dimensions()
    let sb = StringBuilder()
    for r = 0; r < rows; r = r + 1 {
      for c = 0; c < cols; c = c + 1 {
        if c > 0 {
          sb.write_char(',')
        }
        let v = match sheet.get(r, c) {
          Some(cell) => cell.value()
          None => Empty
        }
        sb.write_string(csv_field(v))
      }
      sb.write_char('\n')
    }
    write_text(csv, sb.to_string())
    println("wrote CSV (sheet 0, values only): \{csv}")
  }
  let edit = env("ODS_SET")
  if edit != "" {
    let p = edit.split(",").to_array()
    if p.length() != 4 {
      raise Usage("ODS_SET must be sheet,row,col,number")
    }
    let nums = p.map(fn(x) { parse_number(x.to_owned()) })
    for x in nums {
      if x.is_nan() {
        raise Usage("ODS_SET fields must be numbers")
      }
    }
    let s = nums[0].to_int()
    let r = nums[1].to_int()
    let c = nums[2].to_int()
    let n = nums[3]
    match book.sheet(s) {
      None => raise Usage("no such sheet \{s}")
      Some(sh) => sh.set(r, c, @ods.Cell::new(Number(n)))
    }
    println("edited sheet[\{s}] (\{r},\{c}) = number:\{n}")
  }
  let out = env("ODS_OUTPUT")
  if out != "" {
    let bytes = book.to_ods()
    write_file(out, bytes)
    // Re-read our own output so a written file is never reported unchecked.
    let again = @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
    println(
      "wrote \{out} (\{bytes.length()} bytes); re-read OK, sheets=\{again.sheet_count()}",
    )
  }
}

///|
fn main {
  run() catch {
    @ods.Invalid(why) => {
      println("ERROR: \{why}")
      exit_with(1)
    }
    Usage(why) => {
      println("ERROR: \{why}")
      exit_with(1)
    }
    e => {
      println("FAILED: \{e}")
      exit_with(1)
    }
  }
}
