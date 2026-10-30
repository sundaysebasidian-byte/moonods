// Bounded non-validating internal subset reader. No external I/O.

///|
priv enum DtdEntity {
  Internal(String)
  External(String?, String, String?)
}

///|
priv struct DtdAttribute {
  element : String
  name : String
  tokenized : Bool
  declared_type : String
  default_value : String?
}

///|
priv struct DtdInfo {
  root_name : String
  entities : Map[String, DtdEntity]
  attributes : Array[DtdAttribute]
  notations : Map[String, (String?, String?)]
  mut unread_parameter_entity : Bool
  external_subset : Bool
  external_public_id : String?
  external_system_id : String?
  xml_id_declaration_errors : Array[String]
  instructions : Array[(String, String)]
  mut attribute_work : Int32
}

///|
priv struct DtdReader {
  chars : Array[Char]
  mut at : Int32
  start : Int32
  mut declarations : Int32
}

///|
fn DtdReader::peek(p : DtdReader) -> Char {
  if p.at < p.chars.length() {
    p.chars[p.at]
  } else {
    '\u0000'
  }
}

///|
fn DtdReader::take(p : DtdReader) -> Char raise OdsError {
  if p.at >= p.chars.length() || p.at - p.start >= 65536 {
    raise Invalid("DTD truncated or character budget exceeded")
  }
  let c = p.chars[p.at]
  p.at += 1
  c
}

///|
fn DtdReader::expect(p : DtdReader, expected : Char) -> Unit raise OdsError {
  if p.take() != expected {
    raise Invalid("malformed DTD delimiter")
  }
}

///|
fn DtdReader::word(p : DtdReader, expected : String) -> Unit raise OdsError {
  for c in expected {
    p.expect(c)
  }
}

///|
fn dtd_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn DtdReader::space(p : DtdReader) -> Bool raise OdsError {
  let before = p.at
  while dtd_space(p.peek()) {
    ignore(p.take())
  }
  p.at != before
}

///|
fn DtdReader::required_space(p : DtdReader) -> Unit raise OdsError {
  if !p.space() {
    raise Invalid("DTD whitespace required")
  }
}

///|
fn DtdReader::starts(p : DtdReader, text : String) -> Bool {
  let mut n = p.at
  for c in text {
    if n >= p.chars.length() || p.chars[n] != c {
      return false
    }
    n += 1
  }
  true
}

///|
fn DtdReader::name(
  p : DtdReader,
  token~ : Bool = false,
  qname~ : Bool = false,
) -> String raise OdsError {
  if !(if token { xml_name_char(p.peek()) } else { xml_name_start(p.peek()) }) {
    raise Invalid("invalid DTD name")
  }
  let b = StringBuilder()
  let mut n = 0
  while xml_name_char(p.peek()) {
    b.write_char(p.take())
    n += 1
    if n > 256 {
      raise Invalid("DTD name budget exceeded")
    }
  }
  let value = b.to_string()
  if !token {
    if qname {
      let pieces = value.split(":").map(x => x.to_owned()).collect()
      if pieces.length() > 2 || pieces.any(x => !xml_id_ncname(x)) {
        raise Invalid("DTD element or attribute name must be a QName")
      }
    } else if !xml_id_ncname(value) {
      raise Invalid("DTD entity, notation or PI name must be an NCName")
    }
  }
  value
}

///|
fn DtdReader::literal(p : DtdReader) -> String raise OdsError {
  let quote = p.take()
  if quote != '\'' && quote != '"' {
    raise Invalid("DTD literal must be quoted")
  }
  let b = StringBuilder()
  while p.peek() != quote {
    let c = p.take()
    if c == '\r' {
      if p.peek() == '\n' {
        ignore(p.take())
      }
      b.write_char('\n')
    } else {
      b.write_char(c)
    }
  }
  p.expect(quote)
  let text = b.to_string()
  validate_text(text)
  text
}

///|
fn dtd_public_id(value : String) -> Unit raise OdsError {
  for c in value {
    if !(c == ' ' ||
      c == '\r' ||
      c == '\n' ||
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      "-'()+,./:=?;!*#@$_%".contains(c.to_string())) {
      raise Invalid("invalid DTD public identifier")
    }
  }
}

///|
fn DtdReader::external_id(
  p : DtdReader,
  notation : Bool,
) -> (String?, String?) raise OdsError {
  if p.starts("SYSTEM") {
    p.word("SYSTEM")
    p.required_space()
    (None, Some(p.literal()))
  } else {
    p.word("PUBLIC")
    p.required_space()
    let pubid = p.literal()
    dtd_public_id(pubid)
    let spaced = p.space()
    if p.peek() == '\'' || p.peek() == '"' {
      if !spaced {
        raise Invalid("DTD external ID separator required")
      }
      (Some(pubid), Some(p.literal()))
    } else if notation {
      (Some(pubid), None)
    } else {
      raise Invalid("DTD PUBLIC requires system identifier")
    }
  }
}

///|
fn DtdReader::model(p : DtdReader, depth : Int32) -> Unit raise OdsError {
  if depth > 32 {
    raise Invalid("DTD content model depth exceeded")
  }
  if p.peek() != '(' {
    ignore(p.name(qname=true))
  } else {
    p.expect('(')
    ignore(p.space())
    p.model(depth + 1)
    ignore(p.space())
    let separator = p.peek()
    if separator == ',' || separator == '|' {
      while p.peek() == separator {
        ignore(p.take())
        ignore(p.space())
        p.model(depth + 1)
        ignore(p.space())
      }
    }
    p.expect(')')
  }
  if p.peek() == '?' || p.peek() == '*' || p.peek() == '+' {
    ignore(p.take())
  }
}

///|
fn DtdReader::element_decl(p : DtdReader) -> Unit raise OdsError {
  p.word("<!ELEMENT")
  p.required_space()
  ignore(p.name(qname=true))
  p.required_space()
  if p.starts("EMPTY") {
    p.word("EMPTY")
  } else if p.starts("ANY") {
    p.word("ANY")
  } else {
    // Mixed content begins with #PCDATA, optionally preceded by whitespace.
    let save = p.at
    p.expect('(')
    ignore(p.space())
    if p.starts("#PCDATA") {
      p.word("#PCDATA")
      ignore(p.space())
      let mut has_names = false
      while p.peek() == '|' {
        has_names = true
        ignore(p.take())
        ignore(p.space())
        ignore(p.name(qname=true))
        ignore(p.space())
      }
      p.expect(')')
      if has_names {
        p.expect('*')
      } else if p.peek() == '*' {
        ignore(p.take())
      }
    } else {
      p.at = save
      p.model(0)
    }
  }
  ignore(p.space())
  p.expect('>')
}

///|
fn DtdReader::attribute_type(p : DtdReader) -> String raise OdsError {
  if p.peek() == '(' {
    p.enumeration(false)
    "ENUMERATION"
  } else {
    let kind = p.name()
    match kind {
      "CDATA"
      | "ID"
      | "IDREF"
      | "IDREFS"
      | "ENTITY"
      | "ENTITIES"
      | "NMTOKEN"
      | "NMTOKENS" => kind
      "NOTATION" => {
        p.required_space()
        p.enumeration(true)
        kind
      }
      _ => raise Invalid("invalid DTD attribute type")
    }
  }
}

///|
fn DtdReader::enumeration(p : DtdReader, names : Bool) -> Unit raise OdsError {
  p.expect('(')
  ignore(p.space())
  ignore(p.name(token=!names))
  ignore(p.space())
  while p.peek() == '|' {
    ignore(p.take())
    ignore(p.space())
    ignore(p.name(token=!names))
    ignore(p.space())
  }
  p.expect(')')
}

///|
fn DtdReader::attlist(
  p : DtdReader,
  info : DtdInfo,
  adopt : Bool,
) -> Unit raise OdsError {
  p.word("<!ATTLIST")
  p.required_space()
  let element = p.name(qname=true)
  while true {
    let separated = p.space()
    if p.peek() == '>' {
      ignore(p.take())
      break
    }
    if !separated {
      raise Invalid("DTD attribute separator required")
    }
    let name = p.name(qname=true)
    p.required_space()
    let kind = p.attribute_type()
    if name == "xml:id" && kind != "ID" {
      info.xml_id_declaration_errors.push(
        "xml:id on " + element + " declared as " + kind + " instead of ID",
      )
    }
    p.required_space()
    let default_value = if p.peek() == '#' {
      ignore(p.take())
      match p.name() {
        "REQUIRED" | "IMPLIED" => None
        "FIXED" => {
          p.required_space()
          Some(p.literal())
        }
        _ => raise Invalid("invalid DTD default declaration")
      }
    } else {
      Some(p.literal())
    }
    let normalized = match default_value {
      Some(raw) =>
        // Validate lexical references even when declarations must not be adopted.
        if adopt {
          Some(dtd_normalize_attribute(info, raw, kind != "CDATA"))
        } else {
          dtd_reference_syntax(raw, true)
          None
        }
      None => None
    }
    if adopt &&
      !info.attributes.any(a => a.element == element && a.name == name) {
      if info.attributes.length() >= 256 {
        raise Invalid("DTD attribute budget exceeded")
      }
      info.attributes.push({
        element,
        name,
        tokenized: kind != "CDATA",
        declared_type: kind,
        default_value: normalized,
      })
    }
  }
}

///|
fn dtd_reference_syntax(text : String, attribute : Bool) -> Unit raise OdsError {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let p : DtdReader = { chars, at: 0, start: 0, declarations: 0, }
  while p.at < chars.length() {
    let c = p.take()
    if attribute && c == '<' {
      raise Invalid("less-than in DTD attribute default")
    }
    if c == '&' {
      ignore(p.reference())
    }
    if !attribute && c == '%' {
      raise Invalid("parameter reference inside internal entity declaration")
    }
  }
}

///|
fn DtdReader::reference(p : DtdReader) -> (String?, Char?) raise OdsError {
  if p.peek() == '#' {
    ignore(p.take())
    let base = if p.peek() == 'x' {
      ignore(p.take())
      16
    } else {
      10
    }
    let mut value = 0
    let mut digits = 0
    while p.peek() != ';' {
      let c = p.take()
      let d = if c >= '0' && c <= '9' {
        c.to_int() - 48
      } else if c >= 'a' && c <= 'f' {
        c.to_int() - 87
      } else if c >= 'A' && c <= 'F' {
        c.to_int() - 55
      } else {
        -1
      }
      if d < 0 || d >= base || value > (0x10FFFF - d) / base {
        raise Invalid("invalid DTD character reference")
      }
      value = value * base + d
      digits += 1
    }
    p.expect(';')
    if digits == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
      raise Invalid("invalid DTD character scalar")
    }
    let c = value.unsafe_to_char()
    validate_text(c.to_string())
    (None, Some(c))
  } else {
    let name = p.name()
    p.expect(';')
    (Some(name), None)
  }
}

///|
fn dtd_entity_value(raw : String) -> String raise OdsError {
  dtd_reference_syntax(raw, false)
  let chars : Array[Char] = []
  for c in raw {
    chars.push(c)
  }
  let p : DtdReader = { chars, at: 0, start: 0, declarations: 0, }
  let b = StringBuilder()
  while p.at < chars.length() {
    let c = p.take()
    if c != '&' {
      b.write_char(c)
    } else {
      let (name, character) = p.reference()
      match character {
        Some(c) => b.write_char(c)
        None => b.write_string("&" + name.unwrap() + ";")
      }
    }
  }
  b.to_string()
}

///|
fn DtdReader::entity_decl(
  p : DtdReader,
  info : DtdInfo,
  adopt : Bool,
) -> Unit raise OdsError {
  p.word("<!ENTITY")
  p.required_space()
  let parameter = p.peek() == '%'
  if parameter {
    ignore(p.take())
    p.required_space()
  }
  let name = p.name()
  p.required_space()
  let entity = if p.peek() == '\'' || p.peek() == '"' {
    DtdEntity::Internal(dtd_entity_value(p.literal()))
  } else {
    let (pubid, system) = p.external_id(false)
    let separated = p.space()
    let notation = if !parameter && p.starts("NDATA") {
      if !separated {
        raise Invalid("NDATA separator required")
      }
      p.word("NDATA")
      p.required_space()
      Some(p.name())
    } else {
      None
    }
    DtdEntity::External(pubid, system.unwrap(), notation)
  }
  ignore(p.space())
  p.expect('>')
  if !parameter {
    dtd_check_predefined(name, entity)
  }
  if adopt && !parameter && !info.entities.contains(name) {
    info.entities.set(name, entity)
  }
}

///|
fn read_xml_dtd_prefix(
  chars : Array[Char],
  at : Int32,
  standalone : Bool,
) -> (DtdInfo, Int32) raise OdsError {
  if at < 0 || at >= chars.length() {
    raise Invalid("invalid DOCTYPE offset")
  }
  let p : DtdReader = { chars, at, start: at, declarations: 0, }
  p.word("<!DOCTYPE")
  p.required_space()
  let root_name = p.name(qname=true)
  let separated = p.space()
  let external_subset = p.starts("SYSTEM") || p.starts("PUBLIC")
  let mut external_public_id : String? = None
  let mut external_system_id : String? = None
  if external_subset {
    if !separated {
      raise Invalid("DOCTYPE external identifier separator")
    }
    let (pubid, systemid) = p.external_id(false)
    external_public_id = pubid
    external_system_id = systemid
    ignore(p.space())
  }
  let info : DtdInfo = {
    root_name,
    entities: Map([]),
    attributes: [],
    notations: Map([]),
    unread_parameter_entity: false,
    external_subset,
    external_public_id,
    external_system_id,
    xml_id_declaration_errors: [],
    attribute_work: 0,
    instructions: [],
  }
  if p.peek() == '[' {
    ignore(p.take())
    while true {
      ignore(p.space())
      if p.peek() == ']' {
        ignore(p.take())
        break
      }
      p.declarations += 1
      if p.declarations > 256 {
        raise Invalid("DTD declaration budget exceeded")
      }
      if p.starts("<!--") || p.starts("<?") {
        p.misc_declaration(info)
      } else if p.peek() == '%' {
        ignore(p.take())
        ignore(p.name())
        p.expect(';')
        info.unread_parameter_entity = true
      } else if p.starts("<!ELEMENT") {
        p.element_decl()
      } else if p.starts("<!ATTLIST") {
        p.attlist(info, standalone || !info.unread_parameter_entity)
      } else if p.starts("<!ENTITY") {
        p.entity_decl(info, standalone || !info.unread_parameter_entity)
      } else if p.starts("<!NOTATION") {
        p.word("<!NOTATION")
        p.required_space()
        let name = p.name()
        p.required_space()
        let ids = p.external_id(true)
        ignore(p.space())
        p.expect('>')
        if !info.notations.contains(name) {
          info.notations.set(name, ids)
        }
      } else {
        raise Invalid("invalid internal DTD declaration")
      }
    }
    ignore(p.space())
  }
  p.expect('>')
  (info, p.at)
}

///|
priv struct DtdExpansion {
  mut work : Int32
  mut size : Int32
  active : Array[String]
}

///|
fn dtd_expand_attribute(
  info : DtdInfo,
  raw : String,
  budget : DtdExpansion,
  out : StringBuilder,
  normalize_lines : Bool,
) -> Unit raise OdsError {
  let chars : Array[Char] = []
  for c in raw {
    chars.push(c)
  }
  let p : DtdReader = { chars, at: 0, start: 0, declarations: 0, }
  while p.at < chars.length() {
    budget.work += 1
    info.attribute_work += 1
    if info.attribute_work > 1000000 {
      raise Invalid("DTD document attribute work budget exceeded")
    }
    if budget.work > 100000 {
      raise Invalid("DTD entity work budget exceeded")
    }
    let c = p.take()
    let result = if c == '<' {
      raise Invalid("less-than in entity attribute replacement")
    } else if c != '&' {
      if normalize_lines && c == '\r' && p.peek() == '\n' {
        ignore(p.take())
      }
      Some(if dtd_space(c) { ' ' } else { c })
    } else {
      let (name, character) = p.reference()
      match character {
        Some(c) => Some(c)
        None => {
          let name = name.unwrap()
          match name {
            "amp" => Some('&')
            "lt" => Some('<')
            "gt" => Some('>')
            "quot" => Some('"')
            "apos" => Some('\'')
            _ => {
              if budget.active.contains(name) || budget.active.length() >= 32 {
                raise Invalid("recursive or too-deep entity expansion")
              }
              match info.entities.get(name) {
                Some(Internal(value)) => {
                  budget.active.push(name)
                  dtd_expand_attribute(info, value, budget, out, false)
                  ignore(budget.active.pop())
                }
                Some(External(_, _, _)) =>
                  raise Invalid("external or unparsed entity in attribute")
                None => raise Invalid("undeclared entity in attribute")
              }
              None
            }
          }
        }
      }
    }
    if result is Some(c) {
      budget.size += 1
      if budget.size > 32767 {
        raise Invalid("DTD expanded attribute limit")
      }
      out.write_char(c)
    }
  }
}

///|
fn dtd_normalize_attribute(
  info : DtdInfo,
  raw : String,
  tokenized : Bool,
  normalize_lines~ : Bool = true,
) -> String raise OdsError {
  let out = StringBuilder()
  dtd_expand_attribute(
    info,
    raw,
    { work: 0, size: 0, active: [], },
    out,
    normalize_lines,
  )
  let text = out.to_string()
  if !tokenized {
    return text
  }
  let b = StringBuilder()
  let mut pending = false
  let mut written = false
  for c in text {
    if c == ' ' {
      pending = written
    } else {
      if pending {
        b.write_char(' ')
      }
      b.write_char(c)
      written = true
      pending = false
    }
  }
  b.to_string()
}

///|
fn DtdReader::misc_declaration(
  p : DtdReader,
  info : DtdInfo,
) -> Unit raise OdsError {
  let comment = p.starts("<!--")
  let mut pi_target = ""
  if comment {
    p.word("<!--")
  } else {
    p.word("<?")
    let target = p.name()
    pi_target = target
    if target.to_lower() == "xml" {
      raise Invalid("reserved XML PI target in DTD")
    }
    if !p.starts("?>") {
      p.required_space()
    }
  }
  let end = if comment { "-->" } else { "?>" }
  let body = StringBuilder()
  while !p.starts(end) {
    if comment && p.starts("--") {
      raise Invalid("invalid DTD comment")
    }
    let c = p.take()
    if c == '\r' {
      if p.peek() == '\n' {
        ignore(p.take())
      }
      body.write_char('\n')
    } else {
      body.write_char(c)
    }
  }
  p.word(end)
  validate_text(body.to_string())
  if !comment {
    info.instructions.push((pi_target, body.to_string()))
  }
}

///|
fn dtd_check_predefined(
  name : String,
  entity : DtdEntity,
) -> Unit raise OdsError {
  let expected = match name {
    "lt" => Some('<')
    "amp" => Some('&')
    "gt" => Some('>')
    "apos" => Some('\'')
    "quot" => Some('"')
    _ => None
  }
  if expected is Some(wanted) {
    match entity {
      External(_, _, _) => raise Invalid("predefined entity must be internal")
      Internal(value) => {
        if name != "lt" && name != "amp" && value == wanted.to_string() {
          return
        }
        let chars : Array[Char] = []
        for c in value {
          chars.push(c)
        }
        let p : DtdReader = { chars, at: 0, start: 0, declarations: 0, }
        p.expect('&')
        let (reference, character) = p.reference()
        if reference != None ||
          character != Some(wanted) ||
          p.at != chars.length() {
          raise Invalid("invalid predefined entity replacement")
        }
      }
    }
  }
}
