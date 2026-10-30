// Fixed vocabulary, typed data and escaped text; arbitrary XML is not accepted.

///|
priv struct XmlOutput {
  data : @buffer.Buffer
}

///|
fn XmlOutput::new() -> XmlOutput {
  { data: @buffer.Buffer(), }
}

///|
fn XmlOutput::write_string(self : XmlOutput, s : String) -> Unit raise OdsError {
  let bytes = @utf8.encode(s[:])
  if self.data.length() + bytes.length() > 16777216 {
    raise Invalid("content XML exceeds 16 MiB")
  }
  self.data.write_bytes(bytes[:])
}

///|
fn XmlOutput::to_string(self : XmlOutput) -> String {
  @utf8.decode_lossy(self.data.to_bytes()[:])
}

///|
fn xml_escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    match c {
      '&' => b.write_string("&amp;")
      '<' => b.write_string("&lt;")
      '>' => b.write_string("&gt;")
      '"' => b.write_string("&quot;")
      '\'' => b.write_string("&apos;")
      '\n' => b.write_string("&#10;")
      '\r' => b.write_string("&#13;")
      '\t' => b.write_string("&#9;")
      _ => b.write_char(c)
    }
  }
  b.to_string()
}

///|
fn text_paragraph(s : String) -> String {
  let b = StringBuilder()
  b.write_string("<text:p>")
  let mut spaces = 0
  for c in s {
    if c == ' ' {
      spaces += 1
      continue
    }
    write_text_spaces(b, spaces)
    spaces = 0
    match c {
      '\t' => b.write_string("<text:tab/>")
      '\n' => b.write_string("<text:line-break/>")
      _ => b.write_string(xml_escape(c.to_string()))
    }
  }
  write_text_spaces(b, spaces)
  b.write_string("</text:p>")
  b.to_string()
}

///|
fn write_text_spaces(out : StringBuilder, count : Int32) -> Unit {
  if count == 1 {
    out.write_string("<text:s/>")
  } else if count > 1 {
    out.write_string("<text:s text:c=\"\{count}\"/>")
  }
}

///|
fn pad(n : Int32, size : Int32) -> String {
  let s = n.to_string()
  let b = StringBuilder()
  for _ in 0..<(size - s.length()) {
    b.write_string("0")
  }
  b.write_string(s)
  b.to_string()
}

///|
fn Cell::xml(self : Cell, extra : String) -> String {
  // ODF paragraph whitespace cannot represent a literal CR. Preserve that
  // typed string in office:string-value instead of emitting a misleading p.
  let attribute_text = match self.value {
    Text(s) => s.contains("\r")
    _ => false
  }
  let b = StringBuilder()
  b.write_string("<table:table-cell")
  b.write_string(extra)
  b.write_string(" table:style-name=\"\{self.output_style()}\"")
  if self.formula is Some(f) {
    b.write_string(" table:formula=\"\{xml_escape(f)}\"")
  }
  let display = match self.value {
    Empty => ""
    Text(s) => {
      // Ordinary strings use explicit paragraph controls without duplicated
      // attributes. CR strings use the typed attribute only; no visual claim.
      b.write_string(" office:value-type=\"string\"")
      if attribute_text {
        b.write_string(" office:string-value=\"\{xml_escape(s)}\"")
      }
      s
    }
    Number(n) => {
      let s = finite_number_text(n)
      b.write_string(" office:value-type=\"float\" office:value=\"\{s}\"")
      s
    }
    Percentage(n) => {
      let s = finite_number_text(n)
      b.write_string(" office:value-type=\"percentage\" office:value=\"\{s}\"")
      s
    }
    Currency(n, code) => {
      let s = finite_number_text(n)
      b.write_string(
        " office:value-type=\"currency\" office:value=\"\{s}\" office:currency=\"\{code}\"",
      )
      code + " " + s
    }
    Duration(s) => {
      b.write_string(
        " office:value-type=\"time\" office:time-value=\"\{xml_escape(s)}\"",
      )
      s
    }
    DateTime(s) => {
      b.write_string(
        " office:value-type=\"date\" office:date-value=\"\{xml_escape(s)}\"",
      )
      s
    }
    Boolean(v) => {
      let s = if v { "true" } else { "false" }
      b.write_string(
        " office:value-type=\"boolean\" office:boolean-value=\"\{s}\"",
      )
      s
    }
    Date(y, m, d) => {
      let s = "\{pad(y, 4)}-\{pad(m, 2)}-\{pad(d, 2)}"
      b.write_string(" office:value-type=\"date\" office:date-value=\"\{s}\"")
      s
    }
  }
  b.write_string(">")
  if self.value != Empty && !attribute_text {
    b.write_string(text_paragraph(display))
  }
  b.write_string("</table:table-cell>")
  b.to_string()
}

///|
fn finite_number_text(n : Double) -> String {
  if n == 0.0 && 1.0 / n < 0.0 {
    "-0"
  } else {
    n.to_string()
  }
}
