// Bounded XML reader for ODF data import with internal DTD/entity processing.
// No external entity I/O or recovery. Comments and processing instructions are ignored.

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
  normalize_lines : Bool
  document_part : String
  mut location : String
  events : Array[XmlProcessorEvent]
  mut standalone : Bool
  mut dtd : DtdInfo?
  expansion : ReadEntityExpansion
  declared_types : Map[(Int32, String), String]
  other_ids : Array[(Int32, String, String)]
}

///|
priv struct ReadEntityExpansion {
  mut units : Int32
  active : Array[String]
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
fn xml_name_start(c : Char) -> Bool {
  let n = c.to_int()
  c == ':' ||
  c == '_' ||
  (n >= 0x41 && n <= 0x5A) ||
  (n >= 0x61 && n <= 0x7A) ||
  (n >= 0xC0 && n <= 0xD6) ||
  (n >= 0xD8 && n <= 0xF6) ||
  (n >= 0xF8 && n <= 0x2FF) ||
  (n >= 0x370 && n <= 0x37D) ||
  (n >= 0x37F && n <= 0x1FFF) ||
  (n >= 0x200C && n <= 0x200D) ||
  (n >= 0x2070 && n <= 0x218F) ||
  (n >= 0x2C00 && n <= 0x2FEF) ||
  (n >= 0x3001 && n <= 0xD7FF) ||
  (n >= 0xF900 && n <= 0xFDCF) ||
  (n >= 0xFDF0 && n <= 0xFFFD) ||
  (n >= 0x10000 && n <= 0xEFFFF)
}

///|
fn xml_name_char(c : Char) -> Bool {
  let n = c.to_int()
  xml_name_start(c) ||
  c == '-' ||
  c == '.' ||
  (c >= '0' && c <= '9') ||
  n == 0xB7 ||
  (n >= 0x300 && n <= 0x36F) ||
  (n >= 0x203F && n <= 0x2040)
}

///|
fn ReadXml::name(self : ReadXml) -> String raise OdsError {
  let b = StringBuilder()
  let first = self.peek()
  if !xml_name_start(first) {
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
  while self.at < self.chars.length() && self.peek() != stop {
    if !attribute && self.general_entity_ahead() {
      break
    }
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
    } else if c == '\r' && self.normalize_lines {
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
fn ReadXml::starts_with(self : ReadXml, expected : String) -> Bool {
  let mut offset = 0
  for c in expected {
    if self.at + offset >= self.chars.length() ||
      self.chars[self.at + offset] != c {
      return false
    }
    offset += 1
  }
  true
}

///|
fn ReadXml::cdata(self : ReadXml) -> String raise OdsError {
  for c in "<![CDATA[" {
    self.expect(c)
  }
  let b = StringBuilder()
  let mut units = 0
  while !self.starts_with("]]>") {
    let c = self.take()
    if c == '\r' && self.normalize_lines {
      if self.peek() == '\n' {
        self.at += 1
      }
      b.write_char('\n')
    } else {
      b.write_char(c)
    }
    units += 1
    if units > 32767 {
      raise Invalid("CDATA text exceeds limit")
    }
  }
  self.at += 3
  let value = b.to_string()
  validate_text(value)
  value
}

///|
fn ReadXml::comment(self : ReadXml) -> Unit raise OdsError {
  for c in "<!--" {
    self.expect(c)
  }
  let b = StringBuilder()
  let mut units = 0
  while !self.starts_with("-->") {
    if self.starts_with("--") {
      raise Invalid("double hyphen in XML comment")
    }
    b.write_char(self.take())
    units += 1
    if units > 32767 {
      raise Invalid("XML comment limit")
    }
  }
  self.at += 3
  validate_text(b.to_string())
}

///|
fn ReadXml::instruction(self : ReadXml) -> Unit raise OdsError {
  self.expect('<')
  self.expect('?')
  let target = self.name()
  if !xml_id_ncname(target) {
    raise Invalid("PI target must be an NCName")
  }
  match target {
    "xml" | "xmL" | "xMl" | "xML" | "Xml" | "XmL" | "XMl" | "XML" =>
      raise Invalid("reserved XML PI target")
    _ => ()
  }
  if !self.starts_with("?>") &&
    self.peek() != ' ' &&
    self.peek() != '\t' &&
    self.peek() != '\r' &&
    self.peek() != '\n' {
    raise Invalid("XML PI target separator required")
  }
  self.space()
  let b = StringBuilder()
  let mut units = 0
  while !self.starts_with("?>") {
    let c = self.take()
    if c == '\r' && self.normalize_lines {
      if self.peek() == '\n' {
        self.at += 1
      }
      b.write_char('\n')
    } else {
      b.write_char(c)
    }
    units += 1
    if units > 32767 {
      raise Invalid("XML PI limit")
    }
  }
  self.at += 2
  validate_text(b.to_string())
  self.event("PROCESSING_INSTRUCTION", target, b.to_string())
}

///|
fn ReadXml::misc(self : ReadXml) -> Unit raise OdsError {
  while true {
    self.space()
    if self.starts_with("<!--") {
      self.comment()
    } else if self.starts_with("<?") {
      self.instruction()
    } else {
      break
    }
  }
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
      if first && !xml_name_start(c) {
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
  let element_index = self.nodes
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
    let v = match self.dtd {
      None => self.text(quote, true)
      Some(info) => {
        let raw_value = self.attribute_source(quote)
        let mut tokenized = false
        for attr in info.attributes {
          if attr.element == rawname && attr.name == k {
            tokenized = attr.tokenized
          }
        }
        dtd_normalize_attribute(
          info,
          raw_value,
          tokenized,
          normalize_lines=self.normalize_lines,
        )
      }
    }
    self.expect(quote)
    if raw.contains(k) || raw.length() >= 64 {
      raise Invalid("duplicate/too many XML attributes")
    }
    self.expansion.units += v.length()
    if self.expansion.units > 1048576 {
      raise Invalid("XML expanded values budget exceeded")
    }
    raw.set(k, v)
  }
  match self.dtd {
    Some(info) =>
      for attr in info.attributes {
        if attr.element == rawname && !raw.contains(attr.name) {
          if attr.default_value is Some(value) {
            self.expansion.units += value.length()
            if self.expansion.units > 1048576 {
              raise Invalid("XML default values budget exceeded")
            }
            raw.set(attr.name, value)
          }
        }
      }
    None => ()
  }
  if raw.length() > 64 {
    raise Invalid("too many defaulted XML attributes")
  }
  for k, v in raw {
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
        if c == ':' || (first && !xml_name_start(c)) {
          raise Invalid("invalid namespace prefix")
        }
        first = false
      }
      if first ||
        prefix == "xmlns" ||
        (prefix == "xml" && v != "http://www.w3.org/XML/1998/namespace") ||
        v == "" ||
        v == "http://www.w3.org/2000/xmlns/" ||
        (prefix != "xml" && v == "http://www.w3.org/XML/1998/namespace") {
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
      if self.dtd is Some(info) {
        for attr in info.attributes {
          if attr.element == rawname && attr.name == k {
            self.declared_types.set(
              (element_index, expanded),
              attr.declared_type,
            )
            if attr.declared_type == "ID" && expanded != xml_id_expanded_name {
              self.other_ids.push((element_index, expanded, v))
            }
          }
        }
      }
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
    if self.at >= self.chars.length() {
      raise Invalid("truncated XML element")
    }
    if self.peek() == '<' {
      if self.starts_with("<!--") {
        self.comment()
        continue
      }
      if self.starts_with("<?") {
        self.instruction()
        continue
      }
      if self.starts_with("<![CDATA[") {
        parts.push(ReadText(self.cdata()))
        continue
      }
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
    } else if self.general_entity_ahead() {
      for part in self.expand_content_entity(ns, depth + 1) {
        parts.push(part)
      }
    } else {
      parts.push(ReadText(self.text('<', false)))
    }
  }
  { name, attrs, parts, ns, }
}

///|
fn read_xml(
  text : String,
  document_part~ : String = "",
  id_assignments~ : Array[XmlIdAssignment] = [],
  id_diagnostics~ : Array[XmlIdDiagnostic] = [],
  processor_events~ : Array[XmlProcessorEvent] = [],
) -> ReadElement raise OdsError {
  if text.length() > 4194304 {
    raise Invalid("XML input limit")
  }
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let p : ReadXml = {
    chars,
    at: 0,
    nodes: 0,
    normalize_lines: true,
    document_part,
    location: "prolog",
    events: processor_events,
    standalone: false,
    dtd: None,
    expansion: { units: 0, active: [], },
    declared_types: Map([]),
    other_ids: [],
  }
  if p.peek() == '\uFEFF' {
    p.at += 1
  }
  p.declaration("decoded")
  p.misc()
  if p.starts_with("<!DOCTYPE") {
    let (info, next) = read_xml_dtd_prefix(chars, p.at, p.standalone)
    // Root name agreement is a validity constraint, not a nonvalidating check.
    ignore(info.root_name)
    for (target, data) in info.instructions {
      p.event("PROCESSING_INSTRUCTION", target, data, location="dtd")
    }
    for name, (public_id, system_id) in info.notations {
      p.event(
        "NOTATION_DECLARATION",
        name,
        "",
        public_id~,
        system_id~,
        location="dtd",
      )
    }
    for name, entity in info.entities {
      match entity {
        External(public_id, system_id, Some(notation)) =>
          p.event(
            "UNPARSED_ENTITY_DECLARATION",
            name,
            "",
            public_id~,
            system_id=Some(system_id),
            notation=Some(notation),
            location="dtd",
          )
        _ => ()
      }
    }
    if info.external_subset {
      p.event(
        "EXTERNAL_SUBSET_NOT_READ",
        info.root_name,
        "External subset not fetched",
        public_id=info.external_public_id,
        system_id=info.external_system_id,
        location="dtd",
      )
    }
    if info.unread_parameter_entity {
      p.event(
        "PARAMETER_ENTITY_NOT_READ",
        info.root_name,
        "Parameter entities not expanded",
        location="dtd",
      )
    }
    p.dtd = Some(info)
    p.at = next
    p.misc()
  }
  p.location = "content"
  let root = p.element({ "xml": "http://www.w3.org/XML/1998/namespace" }, 0)
  p.location = "epilog"
  p.misc()
  if p.at != chars.length() {
    raise Invalid("trailing XML content")
  }
  if p.dtd is Some(info) {
    for message in info.xml_id_declaration_errors {
      id_diagnostics.push({
        document_part,
        element_index: -1,
        value: "",
        code: "XML_ID_DECLARATION_TYPE",
        message,
      })
    }
  }
  let ids = process_xml_ids(
    root,
    document_part~,
    declared_types=p.declared_types,
    other_ids=p.other_ids,
  )
  for assignment in ids.assignments {
    id_assignments.push(assignment)
  }
  for diagnostic in ids.errors {
    id_diagnostics.push(diagnostic)
  }
  root
}

///|
// XML 1.0 encoding names are case-insensitive. UTF-16 here requires a BOM;
// explicit endian labels must agree with it. Other encodings remain unsupported.
fn xml_encoding_matches(label : String, source : String) -> Bool {
  let label = label.to_lower()
  match source {
    "utf-8" => label == "utf-8"
    "utf-16le" => label == "utf-16" || label == "utf-16le"
    "utf-16be" => label == "utf-16" || label == "utf-16be"
    _ =>
      label == "utf-8" ||
      label == "utf-16" ||
      label == "utf-16le" ||
      label == "utf-16be"
  }
}

///|
fn ReadXml::declaration(
  p : ReadXml,
  source_encoding : String,
) -> Unit raise OdsError {
  if p.starts_with("<?xml ") ||
    p.starts_with("<?xml\t") ||
    p.starts_with("<?xml\r") ||
    p.starts_with("<?xml\n") {
    // XML declaration is distinct from processing instructions handled by misc().
    p.at += 2
    if p.name() != "xml" {
      raise Invalid("invalid XML declaration target")
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
    p.standalone = fields.get("standalone") == Some("yes")
    for i, key in order {
      if key != "version" && key != "encoding" && key != "standalone" {
        raise Invalid("unsupported XML declaration field")
      }
      if key == "encoding" &&
        (
          i != 1 ||
          !xml_encoding_matches(fields.get(key).unwrap(), source_encoding)
        ) {
        raise Invalid(
          "XML encoding declaration does not match supported source encoding",
        )
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
}
