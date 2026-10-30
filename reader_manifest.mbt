// Package-manifest structural/identity checks; not a full RNG validator.

///|
let read_manifest = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0#"

///|
fn check_package_manifest(
  xml : String,
  names : Array[String],
  id_assignments~ : Array[XmlIdAssignment] = [],
  id_diagnostics~ : Array[XmlIdDiagnostic] = [],
  processor_events~ : Array[XmlProcessorEvent] = [],
) -> Unit raise OdsError {
  let root = read_xml(
    xml,
    document_part="META-INF/manifest.xml",
    id_assignments~,
    id_diagnostics~,
    processor_events~,
  )
  if root.name != read_manifest + "manifest" {
    raise Invalid("expected ODF manifest root")
  }
  let entries : Map[String, String] = Map([])
  for entry in root.elements() {
    if entry.name == read_manifest + "encrypted-key" {
      raise Invalid("encrypted ODF package key material is unsupported")
    }
    if entry.name != read_manifest + "file-entry" {
      if !entry.name.has_prefix(read_manifest) {
        manifest_extension_event(processor_events, entry.name)
        continue
      }
      raise Invalid("unsupported manifest element: \{entry.name}")
    }
    let path = match entry.attrs.get(read_manifest + "full-path") {
      Some(p) => p
      None => raise Invalid("manifest entry missing full-path")
    }
    let mime = match entry.attrs.get(read_manifest + "media-type") {
      Some(m) => m
      None => raise Invalid("manifest entry missing media-type")
    }
    if entries.contains(path) {
      raise Invalid("duplicate manifest full-path")
    }
    if path == "" || path == "mimetype" || path == "META-INF/manifest.xml" {
      raise Invalid("forbidden manifest full-path")
    }
    if path != "/" {
      if path.has_prefix("/") || path.contains("\\") {
        raise Invalid("unsupported absolute manifest path")
      }
      for component in path.split("/") {
        if component == "." || component == ".." {
          raise Invalid("unsafe manifest path component")
        }
      }
      if !names.contains(path) && !path.has_suffix("/") {
        raise Invalid("manifest references absent package file")
      }
    }
    for nested in entry.elements() {
      if nested.name == read_manifest + "encryption-data" {
        raise Invalid("encrypted ODF package content is unsupported")
      }
      if !nested.name.has_prefix(read_manifest) {
        manifest_extension_event(processor_events, nested.name)
      } else {
        raise Invalid("unsupported manifest file-entry content")
      }
    }
    entries.set(path, mime)
  }
  if entries.get("/") != Some(media_type) {
    raise Invalid("manifest root media type disagrees with mimetype")
  }
  for name in names {
    if name != "mimetype" &&
      !name.has_prefix("META-INF/") &&
      !name.has_suffix("/") &&
      !entries.contains(name) {
      raise Invalid("package file missing from manifest: \{name}")
    }
  }
}

///|
fn manifest_extension_event(
  events : Array[XmlProcessorEvent],
  name : String,
) -> Unit raise OdsError {
  if events.length() >= 32768 {
    raise Invalid("XML processor event budget exceeded")
  }
  events.push({
    document_part: "META-INF/manifest.xml",
    sequence: events.length(),
    location: "content",
    kind: "MANIFEST_EXTENSION_NOT_INTERPRETED",
    name,
    data: "Foreign manifest element omitted by data-only import",
    public_id: None,
    system_id: None,
    notation: None,
  })
}
