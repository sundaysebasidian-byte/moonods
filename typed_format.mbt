// Type-bearing number formats prevent Office applications from rewriting the
// ODF currency/percentage/time/dateTime type as an unformatted float.

///|
fn typed_format_key(value : Value) -> String {
  match value {
    Percentage(_) => "percentage"
    Currency(_, code) => "currency_" + code
    Duration(_) => "duration"
    DateTime(_) => "datetime"
    _ => ""
  }
}

///|
fn typed_number_format(value : Value) -> String {
  let key = typed_format_key(value)
  if key == "" {
    return ""
  }
  let name = "__ods_number_" + key
  match value {
    Percentage(_) =>
      "<number:percentage-style style:name=\"\{name}\"><number:number number:decimal-places=\"2\" number:min-integer-digits=\"1\"/><number:text>%</number:text></number:percentage-style>"
    Currency(_, code) =>
      "<number:currency-style style:name=\"\{name}\"><number:currency-symbol>\{code}</number:currency-symbol><number:text> </number:text><number:number number:decimal-places=\"2\" number:min-integer-digits=\"1\"/></number:currency-style>"
    Duration(_) =>
      "<number:time-style style:name=\"\{name}\" number:truncate-on-overflow=\"false\"><number:hours number:style=\"long\"/><number:text>:</number:text><number:minutes number:style=\"long\"/><number:text>:</number:text><number:seconds number:style=\"long\" number:decimal-places=\"9\"/></number:time-style>"
    DateTime(_) =>
      "<number:date-style style:name=\"\{name}\"><number:year number:style=\"long\"/><number:text>-</number:text><number:month number:style=\"long\"/><number:text>-</number:text><number:day number:style=\"long\"/><number:text>T</number:text><number:hours number:style=\"long\"/><number:text>:</number:text><number:minutes number:style=\"long\"/><number:text>:</number:text><number:seconds number:style=\"long\" number:decimal-places=\"9\"/></number:date-style>"
    _ => ""
  }
}

///|
fn Cell::output_style(self : Cell) -> String {
  let key = typed_format_key(self.value)
  if key == "" {
    self.style.id()
  } else {
    "__ods_" + self.style.id() + "_" + key
  }
}

///|
fn Workbook::typed_styles(self : Workbook) -> String raise OdsError {
  let number_defs : Map[String, String] = Map([])
  let cell_defs : Map[String, String] = Map([])
  for sheet in self.sheets {
    for _, cell in sheet.cells {
      let key = typed_format_key(cell.value)
      if key == "" {
        continue
      }
      if !number_defs.contains(key) {
        number_defs.set(key, typed_number_format(cell.value))
      }
      if !cell_defs.contains(cell.output_style()) {
        cell_defs.set(
          cell.output_style(),
          "<style:style style:name=\"\{cell.output_style()}\" style:family=\"table-cell\" style:parent-style-name=\"\{cell.style.id()}\" style:data-style-name=\"__ods_number_\{key}\"/>",
        )
      }
      if number_defs.length() + cell_defs.length() > 1024 {
        raise Invalid("typed number-format definition budget exceeded")
      }
    }
  }
  let names = number_defs.keys().to_array()
  names.sort()
  let cells = cell_defs.keys().to_array()
  cells.sort()
  let out = StringBuilder()
  for name in names {
    out.write_string(number_defs[name])
  }
  for name in cells {
    out.write_string(cell_defs[name])
  }
  out.to_string()
}
