///|
// A bounded business adapter, not a general formula evaluator. All spreadsheet
// and CSV parsing/serialization is delegated to the existing MoonODS API.
suberror ReconcileError {
  Invalid(String)
}

///|
extern "js" fn env(name : String) -> String =
  #| name => process.env[name] || ''

///|
extern "js" fn read_bytes(path : String, limit : Int32) -> Bytes =
  #| (path, limit) => {
  #|   const fs = require('node:fs');
  #|   const stat = fs.statSync(path);
  #|   if (!stat.isFile() || stat.size > limit) throw new Error('input must be a regular file within the byte budget');
  #|   const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
  #|   const chunks = []; let total = 0;
  #|   try {
  #|     const opened = fs.fstatSync(fd);
  #|     if (!opened.isFile() || opened.size > limit) throw new Error('input must be a regular file within the byte budget');
  #|     for (;;) {
  #|       const buf = Buffer.alloc(Math.min(65536, limit + 1 - total));
  #|       const n = fs.readSync(fd, buf, 0, buf.length, null);
  #|       if (!n) break;
  #|       total += n;
  #|       if (total > limit) throw new Error('input exceeds byte budget');
  #|       chunks.push(buf.subarray(0, n));
  #|     }
  #|     return new Uint8Array(Buffer.concat(chunks, total));
  #|   } finally { fs.closeSync(fd); }
  #| }

///|
extern "js" fn decode_csv(bytes : Bytes) -> String =
  #| bytes => new (require('node:util').TextDecoder)('utf-8',{fatal:true}).decode(bytes)

///|
// Same staging policy as ods_tool: individual rename is atomic, multiple
// destinations are not a transaction. No concurrency/crash-recovery promise.
extern "js" fn publish(ods : Bytes, details : String, audit : String) -> Unit =
  #| (ods, details, audit) => {
  #|   const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
  #|   const input = [process.env.RECONCILE_INPUT, process.env.RECONCILE_CHANGES];
  #|   const output = ['reconciled.ods', 'details.csv', 'audit.csv'].map(n => path.join(process.env.RECONCILE_OUTPUT, n));
  #|   const paths = [...input, ...output], staged = [];
  #|   const canonical = p => path.join(fs.realpathSync(path.dirname(path.resolve(p))), path.basename(p));
  #|   for (let i=0; i<paths.length; i++) for (let j=i+1; j<paths.length; j++) {
  #|     const a=fs.existsSync(paths[i]) ? fs.statSync(paths[i]) : null;
  #|     const b=fs.existsSync(paths[j]) ? fs.statSync(paths[j]) : null;
  #|     if (canonical(paths[i]) === canonical(paths[j]) || (a && b && a.dev===b.dev && a.ino===b.ino))
  #|       throw new Error('inputs and outputs must be distinct');
  #|   }
  #|   for (const p of output) if(fs.existsSync(p) && !fs.statSync(p).isFile()) throw new Error('output must be a regular file');
  #|   try {
  #|     for (const [i,data] of [ods,details,audit].entries()) {
  #|       const tmp=path.join(path.dirname(output[i]), '.moonods-'+crypto.randomUUID()+'.tmp');
  #|       const fd=fs.openSync(tmp,'wx',0o600); staged.push([tmp,output[i]]);
  #|       try { fs.writeFileSync(fd,data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  #|     }
  #|     for(const [tmp,dest] of staged) fs.renameSync(tmp,dest);
  #|   } finally { for(const [tmp] of staged) if(fs.existsSync(tmp)) fs.unlinkSync(tmp); }
  #| }

///|
fn text(v : @ods.Value) -> String raise {
  match v {
    Text(s) if s.trim() != "" => s
    _ => raise Invalid("nonblank literal text required")
  }
}

///|
fn quantity(v : @ods.Value) -> Int32 raise {
  match v {
    Number(n) if !n.is_nan() &&
      !n.is_inf() &&
      n >= 0.0 &&
      n <= 10000.0 &&
      n == n.to_int().to_double() => n.to_int()
    _ => raise Invalid("quantity must be an integer in 0..10000")
  }
}

///|
fn cents(v : @ods.Value) -> Int32 raise {
  match v {
    Number(n) if !n.is_nan() && !n.is_inf() && n >= 0.0 && n <= 20000000.0 => {
      let c = (n * 100.0 + 0.5).to_int()
      if c.to_double() / 100.0 != n {
        raise Invalid("amount must have exact whole-cent representation")
      }
      c
    }
    _ => raise Invalid("amount outside bounded nonnegative cents")
  }
}

///|
fn csv_quantity(s : String) -> Int32 raise {
  if s == "" {
    raise Invalid("empty amendment quantity")
  }
  let mut n = 0
  for c in s {
    let d = c.to_int() - 48
    if d < 0 || d > 9 || n > (10000 - d) / 10 {
      raise Invalid("amendment quantity must be decimal digits in 0..10000")
    }
    n = n * 10 + d
  }
  n
}

///|
fn headers(sheet : @ods.Sheet, expected : Array[String]) -> Unit raise {
  let (_, cols) = sheet.dimensions()
  if cols != expected.length() {
    raise Invalid("unexpected business columns")
  }
  for c, name in expected {
    match sheet.get(0, c) {
      Some(cell) if cell.value() == @ods.Value::Text(name) => ()
      _ => raise Invalid("missing or unexpected business header")
    }
  }
}

///|
fn run() -> Unit raise {
  let input = env("RECONCILE_INPUT")
  let amendments = env("RECONCILE_CHANGES")
  if input == "" || amendments == "" || env("RECONCILE_OUTPUT") == "" {
    raise Invalid(
      "set RECONCILE_INPUT, RECONCILE_CHANGES and existing RECONCILE_OUTPUT",
    )
  }
  let imported = @ods.read_ods(
    read_bytes(input, 33554432),
    allow_formatting_loss=env("RECONCILE_ACCEPT_LOSS") == "1",
  )
  let book = imported.workbook()
  if book.sheet_count() != 3 {
    raise Invalid("expected procurement template's three sheets")
  }
  let detail = book.sheet(0).unwrap()
  let budget = book.sheet(1).unwrap()
  if detail.name() != "采购明细" ||
    budget.name() != "预算复核" ||
    book.sheet(2).unwrap().name() != "使用说明" {
    raise Invalid("unexpected template sheet names")
  }
  headers(detail, [
    "订单", "部门", "品目", "数量", "单价", "含税小计", "到货日期",
    "验收", "备注",
  ])
  let (_, budget_cols) = budget.dimensions()
  headers(
    budget,
    if budget_cols == 5 {
      ["部门", "预算", "采购额", "剩余预算", "超预算"]
    } else {
      ["部门", "预算", "采购额", "剩余预算"]
    },
  )
  // Whitelist only these template expressions. Never carry arbitrary formulas
  // (including formulas with external references) into another office file.
  for s in 0..<book.sheet_count() {
    let sheet = book.sheet(s).unwrap()
    let (rows, cols) = sheet.dimensions()
    for r in 0..<rows {
      for c in 0..<cols {
        if sheet.get(r, c) is Some(cell) &&
          cell.expression() is Some(expression) {
          let allowed = if s == 0 && r > 0 && c == 5 {
            "of:=[.D\{r+1}]*[.E\{r+1}]"
          } else if s == 1 && r > 0 && c == 3 {
            "of:=[.B\{r+1}]-[.C\{r+1}]"
          } else {
            ""
          }
          if expression != allowed {
            raise Invalid("untrusted or unsupported template formula")
          }
        }
      }
    }
  }
  let departments : Map[String, (Int32, Int32)] = Map([])
  for row in budget.records() {
    let name = text(row.values["部门"])
    if departments.contains(name) {
      raise Invalid("duplicate budget department")
    }
    departments[name] = (row.row, cents(row.values["预算"]))
  }
  let rows = detail.records()
  let orders : Map[String, Int32] = Map([])
  for row in rows {
    let id = text(row.values["订单"])
    if orders.contains(id) {
      raise Invalid("duplicate order ID")
    }
    orders[id] = row.row
    if !departments.contains(text(row.values["部门"])) {
      raise Invalid("department lacks budget")
    }
    ignore(text(row.values["品目"]))
    ignore(quantity(row.values["数量"]))
    ignore(cents(row.values["单价"]))
    ignore(cents(row.values["含税小计"]))
    match row.values["到货日期"] {
      Date(_, _, _) => ()
      _ => raise Invalid("typed date required")
    }
    match row.values["验收"] {
      Boolean(_) => ()
      _ => raise Invalid("typed acceptance flag required")
    }
    match row.values["备注"] {
      Empty | Text(_) => ()
      _ => raise Invalid("text or empty note required")
    }
  }
  let changes_book = @ods.Workbook::new()
  let changes = changes_book.add_csv_sheet(
    "修正",
    decode_csv(read_bytes(amendments, 8388608)),
  )
  headers(changes, ["订单", "数量"])
  let pending : Map[String, Int32] = Map([])
  for row in changes.records() {
    let id = text(row.values["订单"])
    if !orders.contains(id) {
      raise Invalid("unknown amendment order")
    }
    if pending.contains(id) {
      raise Invalid("duplicate amendment order")
    }
    pending[id] = csv_quantity(
      match row.values["数量"] {
        Text(s) => s
        _ => raise Invalid("CSV quantity must be text")
      },
    )
  }
  let audit_book = @ods.Workbook::new()
  let audit = audit_book.add_sheet("修正轨迹")
  audit.set_row(
    0,
    0,
    ["订单", "旧数量", "新数量", "旧小计缓存", "新小计缓存"].map(s => {
        @ods.Cell::new(Text(s))
      },
    ),
  )
  let totals : Map[String, Int32] = Map([])
  let mut grand = 0
  let mut audit_row = 1
  let mut quantity_changes = 0
  for row in rows {
    let id = text(row.values["订单"])
    let old = quantity(row.values["数量"])
    let count = pending.get(id).unwrap_or(old)
    let price = cents(row.values["单价"])
    if count > 0 && price > 2000000000 / count {
      raise Invalid("line amount exceeds cents budget")
    }
    let amount = count * price
    if grand > 2000000000 - amount {
      raise Invalid("total exceeds cents budget")
    }
    grand += amount
    let name = text(row.values["部门"])
    totals[name] = totals.get(name).unwrap_or(0) + amount
    if old != count {
      quantity_changes += 1
    }
    // Rebuilt stale caches must be visible even without a CSV amendment.
    if pending.contains(id) ||
      row.values["含税小计"] !=
      @ods.Value::Number(amount.to_double() / 100.0) {
      audit.set_row(audit_row, 0, [
        @ods.Cell::new(Text(id)),
        @ods.Cell::new(Number(old.to_double())),
        @ods.Cell::new(Number(count.to_double())),
        @ods.Cell::new(row.values["含税小计"]),
        @ods.Cell::new(Number(amount.to_double() / 100.0)),
      ])
      audit_row += 1
    }
    detail.set(row.row, 3, @ods.Cell::new(Number(count.to_double())))
    detail.set(
      row.row,
      5,
      @ods.Cell::formula(
        "of:=[.D\{row.row+1}]*[.E\{row.row+1}]",
        Number(amount.to_double() / 100.0),
      ),
    )
  }
  budget.set(0, 4, @ods.Cell::new(Text("超预算")))
  let mut exceeded = 0
  for name, (r, limit) in departments {
    let amount = totals.get(name).unwrap_or(0)
    budget.set(r, 2, @ods.Cell::new(Number(amount.to_double() / 100.0)))
    budget.set(
      r,
      3,
      @ods.Cell::formula(
        "of:=[.B\{r+1}]-[.C\{r+1}]",
        Number((limit - amount).to_double() / 100.0),
      ),
    )
    budget.set(r, 4, @ods.Cell::new(Boolean(amount > limit)))
    if amount > limit {
      exceeded += 1
    }
  }
  // Validate every requested export before any output is staged or replaced.
  let details_csv = detail.to_csv(
    use_formula_cache=true,
    reject_formula_like_text=true,
  )
  let audit_csv = audit.to_csv(reject_formula_like_text=true)
  let bytes = book.to_ods()
  let again = @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
  assert_eq(again.sheet_count(), 3)
  publish(bytes, details_csv, audit_csv)
  println(
    "RECONCILED total_cents=\{grand} changed_orders=\{quantity_changes} over_budget_departments=\{exceeded} requested_orders=\{pending.length()} audited_orders=\{audit_row - 1} loss_diagnostics=\{imported.diagnostics().length()}",
  )
  println(
    "Only template arithmetic caches recomputed by this adapter; no general formula evaluation or style preservation.",
  )
}

///|
extern "js" fn exit_with(code : Int32) -> Unit =
  #| code => process.exit(code)

///|
fn main {
  run() catch {
    Invalid(why) => {
      println("REFUSED: \{why}")
      exit_with(1)
    }
    @ods.Invalid(why) => {
      println("REFUSED: \{why}")
      exit_with(1)
    }
    e => {
      println("FAILED: \{e}")
      exit_with(1)
    }
  }
}
