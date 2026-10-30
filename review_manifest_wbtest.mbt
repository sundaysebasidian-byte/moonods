///|
fn manifest_package(xml : Bytes) -> Bytes raise OdsError {
  stored_package([
    ("mimetype", @utf8.encode(media_type[:])),
    ("content.xml", b"<x/>"),
    ("META-INF/manifest.xml", xml),
  ])
}

///|
fn manifest_rejected(xml : String) -> Bool {
  try {
    ignore(
      read_ods_content_noticing(
        manifest_package(@utf8.encode(xml[:])),
        [],
        require_manifest=true,
      ),
    )
    false
  } catch {
    Invalid(_) => true
  }
}

///|
test "manifest XML parsed in both UTF16 byte orders with exact file identity" {
  let xml = test_minimal_manifest()
  for
    data in [
      @utf8.encode(xml[:]),
      test_utf16(xml, true),
      test_utf16(xml, false),
    ] {
    assert_eq(
      read_ods_content_noticing(
        manifest_package(data),
        [],
        require_manifest=true,
      ),
      "<x/>",
    )
  }
  assert_true(
    try {
      ignore(
        read_ods(
          stored_package([
            ("mimetype", @utf8.encode(media_type[:])),
            ("content.xml", b"<x/>"),
          ]),
          allow_formatting_loss=true,
        ),
      )
      false
    } catch {
      Invalid(message) => message == "ODS package manifest missing"
    },
  )
}

///|
test "manifest wrong root missing entries mismatched MIME duplicate and encryption refuse" {
  let open = "<m:manifest xmlns:m='urn:oasis:names:tc:opendocument:xmlns:manifest:1.0'>"
  let root = "<m:file-entry m:full-path='/' m:media-type='application/vnd.oasis.opendocument.spreadsheet'/>"
  let content = "<m:file-entry m:full-path='content.xml' m:media-type='text/xml'/>"
  let close = "</m:manifest>"
  for
    xml in [
      "<x/>",
      open + root + close,
      open + content + close,
      open + root + root + content + close,
      open +
      "<m:file-entry m:full-path='/' m:media-type='wrong'/>" +
      content +
      close,
      open +
      root +
      content +
      "<m:file-entry m:full-path='missing.xml' m:media-type='text/xml'/>" +
      close,
      open +
      root +
      content +
      "<m:file-entry m:full-path='mimetype' m:media-type='text/plain'/>" +
      close,
      open +
      root +
      "<m:file-entry m:full-path='content.xml' m:media-type='text/xml'><m:encryption-data/></m:file-entry>" +
      close,
      open + root + "<m:file-entry m:full-path='content.xml'/>" + close,
      open +
      root +
      content +
      "<m:file-entry m:full-path='../bad' m:media-type=''/>" +
      close,
    ] {
    assert_true(manifest_rejected(xml))
  }
}

///|
test "manifest not schema validation but all present files must be declared" {
  let files = [
    ("mimetype", @utf8.encode(media_type[:])),
    ("content.xml", b"<x/>"),
    ("styles.xml", b"<x/>"),
    ("META-INF/manifest.xml", @utf8.encode(test_minimal_manifest()[:])),
  ]
  assert_true(
    try {
      ignore(
        read_ods_content_noticing(
          stored_package(files),
          [],
          require_manifest=true,
        ),
      )
      false
    } catch {
      Invalid(message) =>
        message == "package file missing from manifest: styles.xml"
    },
  )
}
