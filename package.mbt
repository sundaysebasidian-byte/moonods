let media_type : String = "application/vnd.oasis.opendocument.spreadsheet"

fn manifest_xml() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?><manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"\{media_type}\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>"
}
fn styles_xml() -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-styles\{namespaces} office:version=\"1.3\"><office:styles/></office:document-styles>"
}

// ODF needs mimetype first; zipc Archive sorts paths (META-INF sorts first).
// This small ZIP32 STORED envelope uses zipc's tested File CRC implementation.
// Fixed ASCII paths only, no assets or path input; no timestamps/extras/comments.
fn stored_package(files : Array[(String, Bytes)]) -> Bytes raise OdsError {
  let body = @buffer.Buffer()
  let central = @buffer.Buffer()
  for (path, data) in files {
    let name = @utf8.encode(path[:])
    let offset = body.length()
    let size = data.length()
    if size > 33554432 || offset + size > 33554432 { raise Invalid("package exceeds 32 MiB") }
    let crc = @zip.File::stored_from_bytes(data).decompressed_crc32()
    body.write_int_le(0x04034b50)
    for n in [20, 0, 0, 0, 33] { body.write_uint16_le(n.to_uint16()) }
    for n in [crc, size, size] { body.write_int_le(n) }
    body.write_uint16_le(name.length().to_uint16())
    body.write_uint16_le(0)
    body.write_bytes(name[:])
    body.write_bytes(data[:])
    central.write_int_le(0x02014b50)
    for n in [20, 20, 0, 0, 0, 33] { central.write_uint16_le(n.to_uint16()) }
    for n in [crc, size, size] { central.write_int_le(n) }
    for n in [name.length(), 0, 0, 0, 0] { central.write_uint16_le(n.to_uint16()) }
    central.write_int_le(0)
    central.write_int_le(offset)
    central.write_bytes(name[:])
  }
  let cd_offset = body.length()
  let cd_size = central.length()
  body.write_bytes(central.to_bytes()[:])
  body.write_int_le(0x06054b50)
  for n in [0, 0, files.length(), files.length()] { body.write_uint16_le(n.to_uint16()) }
  body.write_int_le(cd_size)
  body.write_int_le(cd_offset)
  body.write_uint16_le(0)
  if body.length() > 33554432 { raise Invalid("package exceeds 32 MiB") }
  body.to_bytes()
}

/// Return a complete deterministic ODS package. I/O belongs to the caller.
pub fn Workbook::to_ods(self : Workbook) -> Bytes raise OdsError {
  stored_package([
    ("mimetype", @utf8.encode(media_type[:])),
    ("content.xml", @utf8.encode(self.content_xml()[:])),
    ("styles.xml", @utf8.encode(styles_xml()[:])),
    ("META-INF/manifest.xml", @utf8.encode(manifest_xml()[:])),
  ])
}
