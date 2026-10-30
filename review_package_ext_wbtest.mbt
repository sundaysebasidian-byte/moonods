///|
fn extension_package(
  name : String,
  data : Bytes,
  manifest_extra~ : String = "",
) -> Bytes raise OdsError {
  let content = reader_xml_fixture(
    "<t:table-row><t:table-cell o:value-type='string'><x:p>kept</x:p></t:table-cell></t:table-row>",
  )
  let entry = if name.has_prefix("META-INF/") {
    ""
  } else {
    "<m:file-entry m:full-path='" +
    name +
    "' m:media-type='application/octet-stream'/>"
  }
  let manifest = test_minimal_manifest().replace(
    old="</m:manifest>",
    new=entry + manifest_extra + "</m:manifest>",
  )
  stored_package([
    ("mimetype", @utf8.encode(media_type[:])),
    ("content.xml", @utf8.encode(content[:])),
    ("META-INF/manifest.xml", @utf8.encode(manifest[:])),
    (name, data),
  ])
}

///|
test "public extended package safe binary files accepted with explicit losses" {
  for
    path in [
      "Pictures/photo.png", "Object 1/content.xml", "Assets/foo.xml", "META-INF/vendor.xml",
      "资源/模型.bin",
    ] {
    let result = read_ods(
      extension_package(path, b"\xff\x00\x01"),
      allow_formatting_loss=true,
    )
    assert_eq(
      result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
      Text("kept"),
    )
    assert_true(
      result
      .diagnostics()
      .any(d => d.code == "PACKAGE_PART_DROPPED" && d.message.contains(path)),
    )
  }
}

///|
test "signature identification has no extension rule and parses XML without verifying crypto" {
  let raw = "<?sig before?><s:document-signatures xmlns:s='urn:oasis:names:tc:opendocument:xmlns:digitalsignature:1.0' xml:id='signed'/>"
  let result = read_ods(
    extension_package("META-INF/my-signatures", @utf8.encode(raw[:])),
    allow_formatting_loss=true,
  )
  assert_true(result.diagnostics().any(d => d.code == "SIGNATURE_NOT_VERIFIED"))
  assert_true(
    result
    .xml_ids()
    .any(id => {
      id.document_part == "META-INF/my-signatures" && id.value == "signed"
    }),
  )
  assert_true(
    result
    .xml_events()
    .any(e => e.name == "sig" && e.document_part == "META-INF/my-signatures"),
  )
  assert_true(
    try {
      ignore(
        read_ods(
          extension_package("META-INF/my-signatures", b"<a></b>"),
          allow_formatting_loss=true,
        ),
      )
      false
    } catch {
      Invalid(_) => true
    },
  )
}

///|
test "foreign manifest extensions diagnosed without discarding supported cell data" {
  let result = read_ods(
    extension_package(
      "META-INF/vendor.bin",
      b"a",
      manifest_extra="<v:metadata xmlns:v='urn:vendor'><v:x/></v:metadata>",
    ),
    allow_formatting_loss=true,
  )
  assert_true(
    result.diagnostics().any(d => d.code == "PACKAGE_EXTENSION_DROPPED"),
  )
  assert_eq(
    result.workbook().sheet(0).unwrap().get(0, 0).unwrap().value(),
    Text("kept"),
  )
}

///|
test "package path safety is independent from extension allowlists" {
  for
    path in [
      "../evil", "a/../evil", "./evil", "/evil", "a//evil", "a\\evil", "C:evil",
      "a\u0000b",
    ] {
    assert_true(
      try {
        ignore(
          read_ods(extension_package(path, b"x"), allow_formatting_loss=true),
        )
        false
      } catch {
        Invalid(_) => true
      },
    )
  }
}

///|
test "manifest encrypted content refusal precedes ciphertext XML decoding" {
  let manifest = test_minimal_manifest().replace(
    old="m:full-path='content.xml' m:media-type='text/xml'/>",
    new="m:full-path='content.xml' m:media-type='text/xml'><m:encryption-data/></m:file-entry>",
  )
  let message = try {
    ignore(
      read_ods(
        stored_package([
          ("mimetype", @utf8.encode(media_type[:])),
          ("content.xml", b"\xff\xfe\x01"),
          ("META-INF/manifest.xml", @utf8.encode(manifest[:])),
        ]),
        allow_formatting_loss=true,
      ),
    )
    ""
  } catch {
    Invalid(m) => m
  }
  assert_true(message.contains("encrypted ODF"))
}
