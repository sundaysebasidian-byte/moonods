///|
/// XML processor observations, scoped and ordered within a document part.
/// PI data excludes its separating whitespace. External identifiers are metadata,
/// never fetched. Event records do not imply data-only export preserves metadata.
pub(all) struct XmlProcessorEvent {
  document_part : String
  sequence : Int32
  location : String
  kind : String
  name : String
  data : String
  public_id : String?
  system_id : String?
  notation : String?
} derive(Eq, Debug)

///|
fn ReadXml::event(
  p : ReadXml,
  kind : String,
  name : String,
  data : String,
  public_id~ : String? = None,
  system_id~ : String? = None,
  notation~ : String? = None,
  location~ : String = p.location,
) -> Unit raise OdsError {
  if p.events.length() >= 32768 {
    raise Invalid("XML processor event budget exceeded")
  }
  p.events.push({
    document_part: p.document_part,
    sequence: p.events.length(),
    location,
    kind,
    name,
    data,
    public_id,
    system_id,
    notation,
  })
}

///|
/// Stable classification for a recognized-but-unread XML dependency.
/// This is unsupported input, not evidence that its XML is malformed.
pub fn OdsError::is_unread_xml_dependency(self : OdsError) -> Bool {
  match self {
    Invalid(message) => message.has_prefix("XML_DEPENDENCY_NOT_READ:")
  }
}

///|
pub extend XmlProcessorEvent with Eq::{equal, not_equal}

///|
pub extend XmlProcessorEvent with @debug.Debug::{to_repr}
