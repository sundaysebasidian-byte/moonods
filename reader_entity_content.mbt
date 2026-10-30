///|
fn ReadXml::general_entity_ahead(p : ReadXml) -> Bool {
  if p.peek() != '&' || p.starts_with("&#") {
    return false
  }
  !(p.starts_with("&amp;") ||
  p.starts_with("&lt;") ||
  p.starts_with("&gt;") ||
  p.starts_with("&apos;") ||
  p.starts_with("&quot;"))
}

///|
fn ReadXml::attribute_source(
  p : ReadXml,
  quote : Char,
) -> String raise OdsError {
  let b = StringBuilder()
  while p.peek() != quote {
    let c = p.take()
    if c == '<' {
      raise Invalid("raw less-than in XML attribute")
    }
    b.write_char(c)
    if b.to_string().length() > 32767 {
      raise Invalid("XML attribute source limit")
    }
  }
  b.to_string()
}

///|
fn ReadXml::expand_content_entity(
  p : ReadXml,
  ns : Map[String, String],
  depth : Int32,
) -> Array[ReadPart] raise OdsError {
  p.expect('&')
  let name = p.name()
  if !xml_id_ncname(name) {
    raise Invalid("entity reference must be an NCName")
  }
  p.expect(';')
  if p.expansion.active.contains(name) || p.expansion.active.length() >= 32 {
    raise Invalid("recursive or too-deep content entity")
  }
  let info = match p.dtd {
    Some(i) => i
    None => raise Invalid("undeclared general entity")
  }
  let value = match info.entities.get(name) {
    Some(Internal(v)) => v
    Some(External(public_id, system_id, notation)) => {
      // External identifiers are parsed, never fetched by this importer.
      if notation is Some(_) {
        raise Invalid("unparsed entity in XML content")
      }
      p.event(
        "EXTERNAL_ENTITY_NOT_READ",
        name,
        "Value import refused",
        public_id~,
        system_id=Some(system_id),
      )
      raise Invalid(
        "XML_DEPENDENCY_NOT_READ: external general entity not loaded; value import refused",
      )
    }
    None =>
      if !p.standalone && (info.external_subset || info.unread_parameter_entity) {
        raise Invalid(
          "XML_DEPENDENCY_NOT_READ: general entity depends on unread declarations; value import refused",
        )
      } else {
        raise Invalid("undeclared general entity")
      }
  }
  p.expansion.units += value.length()
  if p.expansion.units > 1048576 {
    raise Invalid("content entity expansion budget exceeded")
  }
  p.expansion.active.push(name)
  let chars : Array[Char] = []
  for c in value {
    chars.push(c)
  }
  let child : ReadXml = {
    chars,
    at: 0,
    nodes: p.nodes,
    normalize_lines: false,
    document_part: p.document_part,
    location: p.location,
    events: p.events,
    standalone: p.standalone,
    dtd: p.dtd,
    expansion: p.expansion,
    declared_types: p.declared_types,
    other_ids: p.other_ids,
  }
  let parts : Array[ReadPart] = []
  while child.at < chars.length() {
    if child.starts_with("<!--") {
      child.comment()
    } else if child.starts_with("<?") {
      child.instruction()
    } else if child.starts_with("<![CDATA[") {
      parts.push(ReadText(child.cdata()))
    } else if child.peek() == '<' {
      if child.starts_with("</") {
        raise Invalid("entity replacement crosses element boundary")
      }
      parts.push(ReadElement(child.element(ns, depth)))
    } else if child.general_entity_ahead() {
      for part in child.expand_content_entity(ns, depth) {
        parts.push(part)
      }
    } else {
      parts.push(ReadText(child.text('<', false)))
    }
  }
  p.nodes = child.nodes
  ignore(p.expansion.active.pop())
  parts
}
