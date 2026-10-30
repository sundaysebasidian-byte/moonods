// xml:id processing is a non-fatal layer after XML attribute normalization.
// W3C xml:id 1.0 §§4–6: assign ID type even when lexical/type/unique checks fail.
// No DTD is parsed here. Declaration information is supplied explicitly by the
// enclosing XML processor; absence is not evidence that all DTDs were checked.

///|
let xml_id_expanded_name = "http://www.w3.org/XML/1998/namespace#id"

///|
/// XML element indices are zero-based preorder within document_part.
/// Type assignment is always ID, including values with reported xml:id errors.
/// This is import metadata, not a promise to preserve IDs on data-only export.
pub(all) struct XmlIdAssignment {
  document_part : String
  element_index : Int32
  element_name : String
  attribute_name : String
  value : String
  attribute_type : String
  valid_ncname : Bool
  unique : Bool
  declared_type : String?
} derive(Eq, Debug)

///|
/// Non-fatal xml:id constraint diagnostic; XML well-formedness errors remain
/// the responsibility of the enclosing XML parser, not this diagnostic layer.
pub(all) struct XmlIdDiagnostic {
  document_part : String
  element_index : Int32
  value : String
  code : String
  message : String
} derive(Eq, Debug)

///|
priv struct XmlIdReport {
  assignments : Array[XmlIdAssignment]
  errors : Array[XmlIdDiagnostic]
}

///|
// Input has already undergone XML 1.0 §3.3.3 attribute normalization. The
// additional ID step collapses #x20 only: TAB/LF/CR from character references
// must survive and cause a lexical error, not be silently repaired to a name.
fn xml_id_normalize(value : String) -> String {
  let out = StringBuilder()
  let mut started = false
  let mut pending_space = false
  for c in value {
    if c == ' ' {
      if started {
        pending_space = true
      }
    } else {
      if pending_space {
        out.write_char(' ')
      }
      out.write_char(c)
      started = true
      pending_space = false
    }
  }
  out.to_string()
}

///|
fn xml_id_ncname(value : String) -> Bool {
  let mut first = true
  for c in value {
    if c == ':' || (if first { !xml_name_start(c) } else { !xml_name_char(c) }) {
      return false
    }
    first = false
  }
  !first
}

///|
// declared_types keys: (preorder element index, expanded attribute name).
// other_ids: (preorder element index, expanded attribute name, normalized ID).
// They must originate in actual parser/type information, not guessed schemas.
// The caller supplies every other ID-typed attribute for cross-type uniqueness;
// xml:id entries are ignored here to avoid double-counting the same attribute.
// A fresh invocation is required for each XML document (not each ZIP package).
fn process_xml_ids(
  root : ReadElement,
  document_part~ : String = "",
  declared_types~ : Map[(Int32, String), String] = Map([]),
  other_ids~ : Array[(Int32, String, String)] = [],
) -> XmlIdReport {
  let pending = [root]
  let found : Array[XmlIdAssignment] = []
  let counts : Map[String, Int32] = Map([])
  let mut index = 0
  while !pending.is_empty() {
    let element = pending.remove(pending.length() - 1)
    match element.attrs.get(xml_id_expanded_name) {
      Some(raw) => {
        let value = xml_id_normalize(raw)
        element.attrs.set(xml_id_expanded_name, value)
        counts.set(value, counts.get(value).unwrap_or(0) + 1)
        found.push({
          document_part,
          element_index: index,
          element_name: element.name,
          attribute_name: xml_id_expanded_name,
          value,
          attribute_type: "ID",
          valid_ncname: xml_id_ncname(value),
          unique: true,
          declared_type: declared_types.get((index, xml_id_expanded_name)),
        })
      }
      None => ()
    }
    for i = element.parts.length() - 1; i >= 0; i = i - 1 {
      match element.parts[i] {
        ReadElement(child) => pending.push(child)
        ReadText(_) => ()
      }
    }
    index += 1
  }
  let other_seen : Map[(Int32, String), Bool] = Map([])
  for (element_index, attribute_name, value) in other_ids {
    let key = (element_index, attribute_name)
    if attribute_name != xml_id_expanded_name && !other_seen.contains(key) {
      other_seen.set(key, true)
      counts.set(value, counts.get(value).unwrap_or(0) + 1)
    }
  }
  let assignments : Array[XmlIdAssignment] = []
  let errors : Array[XmlIdDiagnostic] = []
  for item in found {
    let unique = counts.get(item.value) == Some(1)
    assignments.push({ ..item, unique, })
    if !item.valid_ncname {
      errors.push({
        document_part,
        element_index: item.element_index,
        value: item.value,
        code: "XML_ID_INVALID_NCNAME",
        message: "xml:id is assigned ID type, but its normalized value is not an XML 1.0 NCName.",
      })
    }
    if item.declared_type is Some(kind) && kind != "ID" {
      errors.push({
        document_part,
        element_index: item.element_index,
        value: item.value,
        code: "XML_ID_DECLARED_TYPE",
        message: "xml:id is assigned ID type despite a supplied declaration with a non-ID type.",
      })
    }
    if !unique {
      errors.push({
        document_part,
        element_index: item.element_index,
        value: item.value,
        code: "XML_ID_DUPLICATE",
        message: "xml:id is assigned ID type, but its value is not unique among reported ID attributes in this XML document.",
      })
    }
  }
  { assignments, errors, }
}

///|
pub extend XmlIdAssignment with Eq::{equal, not_equal}

///|
pub extend XmlIdAssignment with @debug.Debug::{to_repr}

///|
pub extend XmlIdDiagnostic with Eq::{equal, not_equal}

///|
pub extend XmlIdDiagnostic with @debug.Debug::{to_repr}
