// Conservative formatting import: resolve actual definitions; emit only the
// writer's fixed presets and exact integer-mm widths, never source XML.

///|
let read_style = "urn:oasis:names:tc:opendocument:xmlns:style:1.0#"

///|
let read_number = "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0#"

///|
priv struct ReadFormats {
  defs : Map[String, ReadElement]
  defaults : Map[String, ReadElement]
  numbers : Map[String, ReadElement]
}

///|
priv struct ReadFormatting {
  source : ReadFormats
  presets : ReadFormats
  cell_cache : Map[(String, String), Style?]
  width_cache : Map[(Bool, String), Int32?]
  mut retained_cells : Int32
  mut retained_widths : Int32
}

///|
fn ReadFormats::new() -> ReadFormats {
  { defs: {}, defaults: {}, numbers: {}, }
}

///|
fn read_format_parts(node : ReadElement) -> Array[ReadPart] {
  node.parts.filter(part => {
    match part {
      ReadText(t) => node.name == read_number + "text" || t.trim() != ""
      ReadElement(_) => true
    }
  })
}

///|
fn read_format_equal(
  a : ReadElement,
  b : ReadElement,
  root~ : Bool = true,
) -> Bool {
  if a.name != b.name {
    return false
  }
  let aa = a.attrs.filter((k, _) => !(root && k == read_style + "name"))
  let ba = b.attrs.filter((k, _) => !(root && k == read_style + "name"))
  if aa.length() != ba.length() {
    return false
  }
  for k, v in aa {
    if ba.get(k) != Some(v) {
      return false
    }
  }
  let ap = read_format_parts(a)
  let bp = read_format_parts(b)
  if ap.length() != bp.length() {
    return false
  }
  for i, p in ap {
    match (p, bp[i]) {
      (ReadText(x), ReadText(y)) => if x != y { return false }
      (ReadElement(x), ReadElement(y)) =>
        if !read_format_equal(x, y, root=false) {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
fn ReadFormats::insert(
  self : ReadFormats,
  node : ReadElement,
) -> Unit raise OdsError {
  if self.defs.length() + self.defaults.length() + self.numbers.length() >= 2048 {
    raise Invalid("basic formatting definition budget exceeded")
  }
  let (map, key) = if node.name == read_style + "default-style" {
    (self.defaults, node.attribute(read_style, "family").unwrap_or(""))
  } else if node.name == read_style + "style" {
    (
      self.defs,
      node.attribute(read_style, "family").unwrap_or("") +
      ":" +
      node.attribute(read_style, "name").unwrap_or(""),
    )
  } else if node.name.has_prefix(read_number) {
    (self.numbers, node.attribute(read_style, "name").unwrap_or(""))
  } else {
    return
  }
  if key == "" {
    return
  }
  if map.get(key) is Some(previous) && !read_format_equal(previous, node) {
    raise Invalid(
      "ambiguous duplicate formatting definition: \{read_preview(key)}",
    )
  }
  map.set(key, node)
}

///|
fn ReadFormats::collect(
  self : ReadFormats,
  root : ReadElement,
) -> Unit raise OdsError {
  if root.name != read_office + "document-styles" &&
    root.name != read_office + "document-content" {
    raise Invalid("expected ODF formatting document root")
  }
  for container in root.elements() {
    if container.name == read_office + "styles" ||
      container.name == read_office + "automatic-styles" {
      for definition in container.elements() {
        self.insert(definition)
      }
    } else if root.name == read_office + "document-styles" &&
      ![read_office + "font-face-decls", read_office + "master-styles"].contains(
        container.name,
      ) {
      raise Invalid("unsupported styles document feature")
    }
  }
}

///|
fn read_format_overlay(
  base : Map[String, String],
  child : Map[String, String],
) -> Map[String, String] {
  let result = base.copy()
  for key, value in child {
    result.set(key, value)
  }
  result
}

///|
fn ReadFormats::properties(
  self : ReadFormats,
  family : String,
  name : String?,
  depth~ : Int32 = 0,
  seen~ : Array[String] = [],
) -> Map[String, String]? raise OdsError {
  if depth > 16 {
    return None
  }
  let node = match name {
    None =>
      match self.defaults.get(family) {
        Some(node) => node
        None => return Some(Map([]))
      }
    Some(name) => {
      if seen.contains(name) {
        return None
      }
      match self.defs.get(family + ":" + name) {
        Some(node) => node
        None => return None
      }
    }
  }
  for key, _ in node.attrs {
    if ![
        read_style + "name",
        read_style + "family",
        read_style + "parent-style-name",
        read_style + "data-style-name",
        read_style + "display-name",
      ].contains(key) {
      return None
    }
  }
  let chain = seen.copy()
  if name is Some(name) {
    chain.push(name)
  }
  let parent = node.attribute(read_style, "parent-style-name")
  let props = if parent is Some(parent) {
    match self.properties(family, Some(parent), depth=depth + 1, seen=chain) {
      Some(p) => p
      None => return None
    }
  } else {
    Map([])
  }
  let visited : Array[String] = []
  for property in node.elements() {
    if ![
        read_style + "text-properties",
        read_style + "paragraph-properties",
        read_style + "table-cell-properties",
        read_style + "table-column-properties",
      ].contains(property.name) ||
      visited.contains(property.name) ||
      !property.elements().is_empty() {
      return None
    }
    visited.push(property.name)
    for key, value in property.attrs {
      props.set(property.name + "@" + key, value)
    }
  }
  if node.attribute(read_style, "data-style-name") is Some(data) {
    props.set("#data-style", data)
  }
  Some(props)
}

///|
fn ReadFormats::effective(
  self : ReadFormats,
  family : String,
  name : String?,
) -> Map[String, String]? raise OdsError {
  let base = match self.properties(family, None) {
    Some(p) => p
    None => return None
  }
  match name {
    None => Some(base)
    Some(_) =>
      match self.properties(family, name) {
        Some(p) => Some(read_format_overlay(base, p))
        None => None
      }
  }
}

///|
fn read_props_equal(
  a : Map[String, String],
  b : Map[String, String],
  actual : ReadFormats,
  expected : ReadFormats,
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for key, value in a {
    if key == "#data-style" {
      match (actual.numbers.get(value), b.get(key)) {
        (Some(definition), Some(name)) =>
          match expected.numbers.get(name) {
            Some(target) =>
              if !read_format_equal(definition, target) {
                return false
              }
            None => return false
          }
        _ => return false
      }
    } else if b.get(key) != Some(value) {
      return false
    }
  }
  true
}

///|
fn ReadFormatting::resolve_cell_style(
  self : ReadFormatting,
  name : String?,
  value~ : Value = Empty,
) -> Style? raise OdsError {
  let source = match self.source.effective("table-cell", name) {
    Some(p) => p
    None => return None
  }
  let typed = typed_format_key(value) != ""
  let known_type_format = if typed {
    match source.get("#data-style") {
      Some(name) =>
        match self.source.numbers.get(name) {
          Some(definition) => {
            let expected = read_xml(
              "<office:document-styles\{namespaces}><office:styles>\{typed_number_format(value)}</office:styles></office:document-styles>",
            )
            read_format_equal(definition, expected.elements()[0].elements()[0])
          }
          None => false
        }
      None => false
    }
  } else {
    false
  }
  if typed && !known_type_format {
    return None
  }
  let source = if known_type_format {
    source.filter((key, _) => key != "#data-style")
  } else {
    source
  }
  for preset in [Plain, Header, Highlight, Decimal2, DateISO] {
    match self.presets.effective("table-cell", Some(preset.id())) {
      Some(expected) => {
        let expected = if known_type_format {
          expected.filter((key, _) => key != "#data-style")
        } else {
          expected
        }
        if read_props_equal(source, expected, self.source, self.presets) {
          return Some(preset)
        }
      }
      None => ()
    }
  }
  None
}

///|
// Rational unit conversion: no floating rounding and no guessed pixel DPI.
fn read_width_mm(text : String) -> Int32? {
  let text = text.trim().to_owned()
  let (unit, mul, div) = if text.has_suffix("mm") {
    ("mm", 1L, 1L)
  } else if text.has_suffix("cm") {
    ("cm", 10L, 1L)
  } else if text.has_suffix("in") {
    ("in", 127L, 5L)
  } else if text.has_suffix("pt") {
    ("pt", 127L, 360L)
  } else if text.has_suffix("pc") {
    ("pc", 127L, 30L)
  } else {
    return None
  }
  let raw = text[:text.length() - unit.length()].to_owned()
  let mut num = 0L
  let mut scale = 1L
  let mut fraction = false
  let mut digits = 0
  for i, c in raw {
    if i == 0 && c == '+' {
      continue
    }
    if c == '.' && !fraction {
      fraction = true
      continue
    }
    if c < '0' || c > '9' || digits >= 9 {
      return None
    }
    num = num * 10L + (c.to_int() - 48).to_int64()
    if fraction {
      scale *= 10L
    }
    digits += 1
  }
  if digits == 0 {
    return None
  }
  let numerator = num * mul
  let denominator = scale * div
  if numerator % denominator != 0L {
    return None
  }
  let mm = numerator / denominator
  if mm < 1L || mm > 500L {
    return None
  }
  Some(mm.to_int())
}

///|
fn ReadFormatting::resolve_column_width(
  self : ReadFormatting,
  name : String?,
) -> Int32? raise OdsError {
  let props = match self.source.effective("table-column", name) {
    Some(p) => p
    None => return None
  }
  let width_key = read_style +
    "table-column-properties@" +
    read_style +
    "column-width"
  let optimal_key = read_style +
    "table-column-properties@" +
    read_style +
    "use-optimal-column-width"
  for key, value in props {
    let neutral_break = (
        key ==
        read_style +
        "table-column-properties@urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0#break-before" ||
        key ==
        read_style +
        "table-column-properties@urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0#break-after"
      ) &&
      value == "auto"
    if key != width_key &&
      !(key == optimal_key && value == "false") &&
      !neutral_break {
      return None
    }
  }
  match props.get(width_key) {
    Some(width) => read_width_mm(width)
    None => None
  }
}

///|
fn read_formatting(
  root : ReadElement,
  styles : Array[String],
) -> ReadFormatting raise OdsError {
  let source = ReadFormats::new()
  for xml in styles {
    source.collect(read_xml(xml))
  }
  source.collect(root)
  let presets = ReadFormats::new()
  presets.collect(read_xml(styles_xml()))
  {
    source,
    presets,
    cell_cache: Map([]),
    width_cache: Map([]),
    retained_cells: 0,
    retained_widths: 0,
  }
}

///|
fn ReadFormatting::cell_style(
  self : ReadFormatting,
  name : String?,
  value~ : Value = Empty,
) -> Style? raise OdsError {
  let reference = match name {
    Some(name) => "name:" + name
    None => "default"
  }
  let key = (reference, typed_format_key(value))
  match self.cell_cache.get(key) {
    Some(cached) => cached
    None => {
      if self.cell_cache.length() >= 2049 {
        return None
      }
      let resolved = self.resolve_cell_style(name, value~)
      if name is None ||
        self.source.defs.contains("table-cell:" + name.unwrap_or("")) {
        self.cell_cache.set(key, resolved)
      }
      resolved
    }
  }
}

///|
fn ReadFormatting::column_width(
  self : ReadFormatting,
  name : String?,
) -> Int32? raise OdsError {
  let key = (name is Some(_), name.unwrap_or(""))
  match self.width_cache.get(key) {
    Some(cached) => cached
    None => {
      let resolved = self.resolve_column_width(name)
      if self.width_cache.length() < 2049 &&
        (
          name is None ||
          self.source.defs.contains("table-column:" + name.unwrap_or(""))
        ) {
        self.width_cache.set(key, resolved)
      }
      resolved
    }
  }
}
