// Read / inspect / edit / convert an external .ods through the public API.
// JS target only: the file adapters below use Node. The reader itself is pure
// MoonBit. Configuration is by environment variables (no fake UI):
//   ODS_INPUT          required, path of the .ods to read
//   ODS_ACCEPT_LOSS=1  opt in to lossy import (formatting etc. is dropped);
//                      without it any item that would be lost is a refusal
//   ODS_CSV            optional, export sheet 0 after edits (no merges)
//   ODS_CSV_CACHE=0    reject formulas; default retains legacy cache export
//                      and reports each dropped formula expression
//   ODS_CSV_REJECT_FORMULA_TEXT=1  reject formula-like Text fields
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
extern "js" fn write_exports(
  csv : String,
  csv_data : Bytes,
  ods : String,
  ods_data : Bytes,
) -> Unit =
  #| (csv, csvData, ods, odsData) => {
  #|   const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
  #|   const staged = [];
  #|   try {
  #|     // Reject predictable destination-type errors before staging or commits.
  #|     for (const dest of [csv, ods]) {
  #|       if (dest && fs.existsSync(dest) && !fs.statSync(dest).isFile())
  #|         throw new Error('output destination must be a regular file: ' + dest);
  #|     }
  #|     for (const [dest, data] of [[csv, csvData], [ods, odsData]]) {
  #|       if (!dest) continue;
  #|       const tmp = path.join(path.dirname(dest), '.moonods-' + crypto.randomUUID() + '.tmp');
  #|       const fd = fs.openSync(tmp, 'wx', 0o600);
  #|       staged.push([tmp, dest]);
  #|       try { fs.writeFileSync(fd, data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  #|     }
  #|     // All staging succeeds before any destination is replaced. Each rename
  #|     // is atomic; two destinations are not a filesystem transaction.
  #|     for (const [tmp, dest] of staged) fs.renameSync(tmp, dest);
  #|   } finally {
  #|     for (const [tmp] of staged) if (fs.existsSync(tmp)) fs.unlinkSync(tmp);
  #|   }
  #| }

///|
extern "js" fn parse_number(s : String) -> Double =
  #| (s) => (s.trim() === '' ? NaN : Number(s))

///|
extern "js" fn text_bytes(data : String) -> Bytes =
  #| d => new Uint8Array(Buffer.from(d, 'utf8'))

///|
extern "js" fn path_error(
  input : String,
  csv : String,
  output : String,
) -> String =
  #| (input, csv, output) => {
  #|   const fs = require('node:fs'), path = require('node:path');
  #|   const paths = [input, csv, output].filter(Boolean);
  #|   const identity = p => fs.existsSync(p) ? fs.statSync(p) : null;
  #|   const canonical = p => {
  #|     const full = path.resolve(p), parent = path.dirname(full);
  #|     return fs.existsSync(parent) ? path.join(fs.realpathSync(parent), path.basename(full)) : full;
  #|   };
  #|   for (let i = 0; i < paths.length; i++) for (let j = i + 1; j < paths.length; j++) {
  #|     const a = identity(paths[i]), b = identity(paths[j]);
  #|     if (canonical(paths[i]) === canonical(paths[j]) || (a && b && a.dev === b.dev && a.ino === b.ino))
  #|       return 'input, CSV and ODS output paths must be distinct';
  #|   }
  #|   return '';
  #| }

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
  let out = env("ODS_OUTPUT")
  let conflict = path_error(input, csv, out)
  if conflict != "" {
    raise Usage(conflict)
  }
  let edit = env("ODS_SET")
  if edit != "" {
    let p = edit.split(",").to_array()
    if p.length() != 4 {
      raise Usage("ODS_SET must be sheet,row,col,number")
    }
    let nums = p.map(fn(x) { parse_number(x.to_owned()) })
    for x in nums {
      if x.is_nan() || x.is_inf() {
        raise Usage("ODS_SET fields must be finite numbers")
      }
    }
    for i in 0..<3 {
      if nums[i] < 0.0 ||
        nums[i] > 2147483647.0 ||
        nums[i] != nums[i].to_int().to_double() {
        raise Usage("ODS_SET indices must be nonnegative integers")
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
    println(
      "FORMULA_CACHE_WARNING: edits never recalculate formulas; application open/save may retain stale caches",
    )
  }
  let cache_policy = env("ODS_CSV_CACHE")
  if cache_policy != "" && cache_policy != "0" && cache_policy != "1" {
    raise Usage("ODS_CSV_CACHE must be 0 or 1")
  }
  let use_cache = cache_policy != "0"
  // Prepare and validate every requested export before touching destinations.
  let csv_text = if csv != "" {
    book
    .sheet(0)
    .unwrap()
    .to_csv(
      use_formula_cache=use_cache,
      reject_formula_like_text=env("ODS_CSV_REJECT_FORMULA_TEXT") == "1",
    )
  } else {
    ""
  }
  let bytes = if out != "" {
    let bytes = book.to_ods()
    let again = @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
    println("re-read OK, sheets=\{again.sheet_count()}")
    bytes
  } else {
    b""
  }
  if csv != "" && use_cache {
    let sheet = book.sheet(0).unwrap()
    let (rows, cols) = sheet.dimensions()
    for row in 0..<rows {
      for col in 0..<cols {
        if sheet.get(row, col) is Some(cell) && cell.expression() is Some(_) {
          println(
            "CSV_FORMULA_DROPPED sheet=\{sheet.name()} row=\{row} col=\{col}: stored cache exported; no recalculation",
          )
        }
      }
    }
  }
  write_exports(csv, text_bytes(csv_text), out, bytes)
  if csv != "" {
    println("wrote CSV (sheet 0, after edits, values only): \{csv}")
  }
  if out != "" {
    println("wrote \{out} (\{bytes.length()} bytes)")
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
