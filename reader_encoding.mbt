// Bounded UTF-8 and BOM-marked UTF-16 XML input. ZIP entry names stay UTF-8.

///|
fn ods_xml_decode(data : Bytes) -> String raise OdsError {
  if data.length() > 4194304 {
    raise Invalid("XML byte limit")
  }
  let little = data.length() >= 2 && data[0] == b'\xFF' && data[1] == b'\xFE'
  let big = data.length() >= 2 && data[0] == b'\xFE' && data[1] == b'\xFF'
  let encoding = if little {
    "utf-16le"
  } else if big {
    "utf-16be"
  } else {
    "utf-8"
  }
  let text = if little || big {
    if data.length() % 2 != 0 {
      raise Invalid("odd UTF-16 byte count")
    }
    let b = StringBuilder()
    b.write_char('\uFEFF')
    let mut i = 2
    while i < data.length() {
      let first = if little {
        data[i].to_int() | (data[i + 1].to_int() << 8)
      } else {
        (data[i].to_int() << 8) | data[i + 1].to_int()
      }
      i += 2
      let scalar = if first >= 0xD800 && first <= 0xDBFF {
        if i >= data.length() {
          raise Invalid("truncated UTF-16 surrogate")
        }
        let second = if little {
          data[i].to_int() | (data[i + 1].to_int() << 8)
        } else {
          (data[i].to_int() << 8) | data[i + 1].to_int()
        }
        if second < 0xDC00 || second > 0xDFFF {
          raise Invalid("invalid UTF-16 surrogate pair")
        }
        i += 2
        0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
      } else {
        if first >= 0xDC00 && first <= 0xDFFF {
          raise Invalid("unpaired UTF-16 low surrogate")
        }
        first
      }
      b.write_char(scalar.unsafe_to_char())
    }
    b.to_string()
  } else {
    ods_zip_utf8(data)
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
    document_part: "",
    location: "declaration",
    events: [],
    standalone: false,
    dtd: None,
    expansion: { units: 0, active: [], },
    declared_types: Map([]),
    other_ids: [],
  }
  if p.peek() == '\uFEFF' {
    p.at += 1
  }
  p.declaration(encoding)
  text
}
