// Strict bounded XML subset for ODF data import. No DTD, entities, CDATA,
// processing instructions other than the initial XML declaration, or recovery.

///|
priv enum ReadPart {
  ReadText(String)
  ReadElement(ReadElement)
}

///|
priv struct ReadElement {
  name : String
  attrs : Map[String, String]
  parts : Array[ReadPart]
  ns : Map[String, String]
}

///|
priv struct ReadXml {
  chars : Array[Char]
  mut at : Int32
  mut nodes : Int32
}

///|
fn ReadXml::peek(self : ReadXml) -> Char {
  if self.at < self.chars.length() {
    self.chars[self.at]
  } else {
    '\u0000'
  }
}

///|
fn ReadXml::take(self : ReadXml) -> Char raise OdsError {
  if self.at >= self.chars.length() {
    raise Invalid("truncated XML")
  }
  let c = self.chars[self.at]
  self.at += 1
  c
}

///|
fn ReadXml::expect(self : ReadXml, c : Char) -> Unit raise OdsError {
  if self.take() != c {
    raise Invalid("malformed XML delimiter")
  }
}

///|
fn ReadXml::space(self : ReadXml) -> Unit {
  while self.peek() == ' ' ||
        self.peek() == '\n' ||
        self.peek() == '\r' ||
        self.peek() == '\t' {
    self.at += 1
  }
}

///|
fn xml_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == ':' ||
  c == '-' ||
  c == '_' ||
  c == '.'
}

///|
fn ReadXml::name(self : ReadXml) -> String raise OdsError {
  let b = StringBuilder()
  let first = self.peek()
  if !((first >= 'a' && first <= 'z') ||
    (first >= 'A' && first <= 'Z') ||
    first == '_') {
    raise Invalid("unsupported XML name")
  }
  while xml_name_char(self.peek()) {
    b.write_char(self.take())
    if b.to_string().length() > 256 {
      raise Invalid("XML name limit")
    }
  }
  b.to_string()
}

///|
fn ReadXml::text(
  self : ReadXml,
  stop : Char,
  attribute : Bool,
) -> String raise OdsError {
  let b = StringBuilder()
  let mut units = 0
  while self.peek() != stop {
    let c = self.take()
    if !attribute &&
      c == ']' &&
      self.at + 1 < self.chars.length() &&
      self.chars[self.at] == ']' &&
      self.chars[self.at + 1] == '>' {
      raise Invalid("raw ]]> is forbidden in XML text")
    }
    if attribute && c == '<' {
      raise Invalid("raw less-than in XML attribute")
    }
    if c == '&' {
      let e = StringBuilder()
      while self.peek() != ';' {
        e.write_char(self.take())
        if e.to_string().length() > 16 {
          raise Invalid("entity length limit")
        }
      }
      self.expect(';')
      let entity = e.to_string()
      let decoded = match entity {
        "amp" => '&'
        "lt" => '<'
        "gt" => '>'
        "quot" => '"'
        "apos" => '\''
        _ => {
          let mut n = 0
          let mut digits = 0
          let mut base = 10
          let mut index = 0
          for d in entity {
            if index == 0 {
              if d != '#' {
                raise Invalid("custom XML entities forbidden")
              }
            } else if index == 1 && d == 'x' {
              base = 16
            } else {
              let v = if d >= '0' && d <= '9' {
                d.to_int() - 48
              } else if d >= 'a' && d <= 'f' {
                d.to_int() - 87
              } else if d >= 'A' && d <= 'F' {
                d.to_int() - 55
              } else {
                -1
              }
              if v < 0 || v >= base || n > (0x10FFFF - v) / base {
                raise Invalid("invalid numeric XML entity")
              }
              n = n * base + v
              digits += 1
            }
            index += 1
          }
          if digits == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) {
            raise Invalid("invalid XML code point")
          }
          n.unsafe_to_char()
        }
      }
      b.write_char(decoded)
    } else if c == '\r' {
      if self.peek() == '\n' {
        self.at += 1
      }
      b.write_char(if attribute { ' ' } else { '\n' })
    } else {
      b.write_char(if attribute && (c == '\n' || c == '\t') { ' ' } else { c })
    }
    units += 1
    if units > 32767 {
      raise Invalid("XML text/attribute exceeds limit")
    }
  }
  let s = b.to_string()
  validate_text(s)
  s
}

///|
fn expanded_name(
  name : String,
  ns : Map[String, String],
  attribute : Bool,
) -> String raise OdsError {
  let pieces = name.split(":").map(x => x.to_owned()).collect()
  for piece in pieces {
    let mut first = true
    for c in piece {
      if first &&
        !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_') {
        raise Invalid("invalid qualified XML name")
      }
      first = false
    }
    if first {
      raise Invalid("empty XML name component")
    }
  }
  if pieces.length() == 1 {
    if attribute {
      name
    } else {
      "\{ns.get("").unwrap_or("")}#\{name}"
    }
  } else if pieces.length() == 2 && pieces[1] != "" {
    match ns.get(pieces[0]) {
      Some(uri) => "\{uri}#\{pieces[1]}"
      None => raise Invalid("unbound XML namespace")
    }
  } else {
    raise Invalid("invalid qualified XML name")
  }
}

///|
fn ReadXml::element(
  self : ReadXml,
  parent : Map[String, String],
  depth : Int32,
) -> ReadElement raise OdsError {
  if depth > 32 || self.nodes >= 65536 {
    raise Invalid("XML depth/node budget exceeded")
  }
  self.nodes += 1
  self.expect('<')
  let rawname = self.name()
  let raw : Map[String, String] = Map([])
  let ns : Map[String, String] = Map([])
  for k, v in parent {
    ns.set(k, v)
  }
  while true {
    let before = self.at
    self.space()
    if self.peek() == '>' || self.peek() == '/' {
      break
    }
    if self.at == before {
      raise Invalid("XML attribute requires whitespace")
    }
    let k = self.name()
    self.space()
    self.expect('=')
    self.space()
    let quote = self.take()
    if quote != '\'' && quote != '"' {
      raise Invalid("XML attribute must be quoted")
    }
    let v = self.text(quote, true)
    self.expect(quote)
    if raw.contains(k) || raw.length() >= 64 {
      raise Invalid("duplicate/too many XML attributes")
    }
    raw.set(k, v)
    if k == "xmlns" {
      if v == "http://www.w3.org/2000/xmlns/" ||
        v == "http://www.w3.org/XML/1998/namespace" {
        raise Invalid("reserved namespace URI")
      }
      ns.set("", v)
    } else if k.has_prefix("xmlns:") {
      let prefix = k[6:].to_owned()
      let mut first = true
      for c in prefix {
        if c == ':' ||
          (
            first &&
            !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_')
          ) {
          raise Invalid("invalid namespace prefix")
        }
        first = false
      }
      if first ||
        prefix == "xmlns" ||
        prefix == "xml" ||
        v == "" ||
        v == "http://www.w3.org/2000/xmlns/" ||
        v == "http://www.w3.org/XML/1998/namespace" {
        raise Invalid("unsupported namespace rebinding")
      }
      ns.set(prefix, v)
    }
  }
  let name = expanded_name(rawname, ns, false)
  let attrs : Map[String, String] = Map([])
  for k, v in raw {
    if k != "xmlns" && !k.has_prefix("xmlns:") {
      let expanded = expanded_name(k, ns, true)
      if attrs.contains(expanded) {
        raise Invalid("duplicate expanded XML attribute")
      }
      attrs.set(expanded, v)
    }
  }
  let parts : Array[ReadPart] = []
  if self.peek() == '/' {
    self.at += 1
    self.expect('>')
    return { name, attrs, parts, ns, }
  }
  self.expect('>')
  while true {
    if self.peek() == '<' {
      if self.at + 1 < self.chars.length() && self.chars[self.at + 1] == '/' {
        self.at += 2
        let close = self.name()
        self.space()
        self.expect('>')
        if close != rawname {
          raise Invalid("mismatched XML closing name")
        }
        break
      }
      parts.push(ReadElement(self.element(ns, depth + 1)))
    } else {
      parts.push(ReadText(self.text('<', false)))
    }
  }
  { name, attrs, parts, ns, }
}

///|
fn read_xml(text : String) -> ReadElement raise OdsError {
  if text.length() > 4194304 {
    raise Invalid("XML input limit")
  }
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let p = { chars, at: 0, nodes: 0, }
  if p.peek() == '\uFEFF' {
    p.at += 1
  }
  if p.at + 5 < chars.length() && chars[p.at] == '<' && chars[p.at + 1] == '?' {
    // Declaration only; all other processing instructions are unsupported.
    p.at += 2
    if p.name() != "xml" {
      raise Invalid("processing instructions unsupported")
    }
    let fields : Map[String, String] = Map([])
    let order : Array[String] = []
    while p.peek() != '?' {
      let before = p.at
      p.space()
      if p.peek() == '?' {
        break
      }
      if before == p.at || fields.length() >= 3 {
        raise Invalid("malformed XML declaration")
      }
      let key = p.name()
      p.space()
      p.expect('=')
      p.space()
      let quote = p.take()
      if quote != '\'' && quote != '"' {
        raise Invalid("invalid XML declaration quote")
      }
      let value_start = p.at
      let value = p.text(quote, true)
      for i in value_start..<p.at {
        if p.chars[i] == '&' {
          raise Invalid("entity references forbidden in XML declaration")
        }
      }
      p.expect(quote)
      if fields.contains(key) {
        raise Invalid("duplicate XML declaration field")
      }
      fields.set(key, value)
      order.push(key)
    }
    p.expect('?')
    p.expect('>')
    if order.is_empty() ||
      order[0] != "version" ||
      fields.get("version") != Some("1.0") {
      raise Invalid("XML 1.0 declaration required")
    }
    for i, key in order {
      if key != "version" && key != "encoding" && key != "standalone" {
        raise Invalid("unsupported XML declaration field")
      }
      if key == "encoding" &&
        (
          i != 1 ||
          (fields.get(key) != Some("UTF-8") && fields.get(key) != Some("utf-8"))
        ) {
        raise Invalid("only UTF-8 XML supported")
      }
      if key == "standalone" &&
        (
          i != order.length() - 1 ||
          (fields.get(key) != Some("yes") && fields.get(key) != Some("no"))
        ) {
        raise Invalid("invalid standalone declaration")
      }
    }
  }
  p.space()
  let root = p.element({ "xml": "http://www.w3.org/XML/1998/namespace" }, 0)
  p.space()
  if p.at != chars.length() {
    raise Invalid("trailing XML content")
  }
  root
}
