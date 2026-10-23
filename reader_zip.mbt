///|
// ZIP32 only. All arithmetic operands are bounded before they are added.
fn ods_zip_u16(data : Bytes, pos : Int32) -> Int32 raise OdsError {
  if pos < 0 || pos > data.length() - 2 {
    raise Invalid("truncated ZIP")
  }
  data[pos].to_int() | (data[pos + 1].to_int() << 8)
}

///|
fn ods_zip_u32(data : Bytes, pos : Int32) -> Int32 raise OdsError {
  ods_zip_u16(data, pos) | (ods_zip_u16(data, pos + 2) << 16)
}

///|
fn ods_zip_size(data : Bytes, pos : Int32) -> Int32 raise OdsError {
  let n = ods_zip_u32(data, pos)
  if n < 0 || n > 33554432 {
    raise Invalid("unsupported ZIP size or ZIP64")
  }
  n
}

///|
fn ods_zip_extra(
  data : Bytes,
  start : Int32,
  length : Int32,
) -> Unit raise OdsError {
  let end = start + length
  if end > data.length() {
    raise Invalid("truncated ZIP extra field")
  }
  let mut p = start
  while p < end {
    if end - p < 4 {
      raise Invalid("invalid ZIP extra field")
    }
    let tag = ods_zip_u16(data, p)
    let size = ods_zip_u16(data, p + 2)
    if tag == 1 {
      raise Invalid("ZIP64 is unsupported")
    }
    p = p + 4 + size
    if p > end {
      raise Invalid("truncated ZIP extra field")
    }
  }
}

///|
fn ods_zip_utf8(data : Bytes) -> String raise OdsError {
  @utf8.decode(data[:]) catch {
    _ => raise Invalid("invalid ZIP/XML UTF-8")
  }
}

///|
fn ods_zip_inflate(data : Bytes, budget : Int32) -> Bytes raise OdsError {
  let decoder = @flate.Inflater()
  let scratch = FixedArray::make(8192, b'\x00')
  let out = @buffer.Buffer()
  let mut consumed = 0
  for ;; {
    let status = decoder.step(data[consumed:], scratch.mut_view(), end=true) catch {
      _ => raise Invalid("invalid DEFLATE stream")
    }
    let used = decoder.last_consumed()
    let produced = decoder.last_produced()
    if produced > budget - out.length() {
      raise Invalid("ODS exceeds 4 MiB inflated budget")
    }
    for i in 0..<produced {
      out.write_byte(scratch[i])
    }
    consumed = consumed + used
    if status is Done {
      if consumed != data.length() {
        raise Invalid("trailing DEFLATE bytes")
      }
      return out.to_bytes()
    }
    if status is NeedMoreInput || (used == 0 && produced == 0) {
      raise Invalid("truncated DEFLATE stream")
    }
  }
}

///|
// Every archive entry is checked, even entries not used by the XML reader.
// No filesystem access, extraction paths, or unbounded inflate convenience API.
fn read_ods_content_noticing(
  data : Bytes,
  omitted : Array[String],
) -> String raise OdsError {
  let length = data.length()
  if length < 22 || length > 33554432 {
    raise Invalid("invalid ODS ZIP input size")
  }
  let mut end = length - 22
  let min_end = if length > 65557 { length - 65557 } else { 0 }
  while end >= min_end {
    if ods_zip_u32(data, end) == 0x06054b50 &&
      end + 22 + ods_zip_u16(data, end + 20) == length {
      break
    }
    end = end - 1
  }
  if end < min_end {
    raise Invalid("ZIP end record missing")
  }
  let count = ods_zip_u16(data, end + 10)
  if ods_zip_u16(data, end + 4) != 0 ||
    ods_zip_u16(data, end + 6) != 0 ||
    ods_zip_u16(data, end + 8) != count {
    raise Invalid("multi-disk ZIP is unsupported")
  }
  if count == 0 || count > 128 {
    raise Invalid("ZIP entry count exceeds budget")
  }
  let cd_size = ods_zip_size(data, end + 12)
  let cd_start = ods_zip_size(data, end + 16)
  if cd_start + cd_size != end {
    raise Invalid("invalid ZIP directory or ZIP64")
  }
  let names : Array[String] = []
  let spans : Array[(Int32, Int32)] = []
  let mut covered = 0
  let mut p = cd_start
  let mut total = 0
  let mut content : String? = None
  let mut mimetype = false
  for _ in 0..<count {
    if p > end - 46 || ods_zip_u32(data, p) != 0x02014b50 {
      raise Invalid("invalid ZIP directory")
    }
    let version = ods_zip_u16(data, p + 6)
    let flags = ods_zip_u16(data, p + 8)
    let compression = ods_zip_u16(data, p + 10)
    if version > 20 ||
      (flags & 0xF7F1) != 0 ||
      (compression != 0 && compression != 8) ||
      (compression == 0 && (flags & 6) != 0) {
      raise Invalid("encrypted or unsupported ZIP entry")
    }
    let crc = ods_zip_u32(data, p + 16)
    let packed = ods_zip_size(data, p + 20)
    let unpacked = ods_zip_size(data, p + 24)
    if unpacked > 4194304 - total {
      raise Invalid("ODS exceeds 4 MiB inflated budget")
    }
    let name_len = ods_zip_u16(data, p + 28)
    let extra_len = ods_zip_u16(data, p + 30)
    let comment_len = ods_zip_u16(data, p + 32)
    if ods_zip_u16(data, p + 34) != 0 {
      raise Invalid("multi-disk ZIP entry")
    }
    let next = p + 46 + name_len + extra_len + comment_len
    if name_len == 0 || next > end {
      raise Invalid("invalid ZIP entry name")
    }
    let name_bytes = data[p + 46:p + 46 + name_len].to_owned()
    let name = ods_zip_utf8(name_bytes)
    let allowed = [
      "mimetype", "content.xml", "styles.xml", "meta.xml", "settings.xml", "manifest.rdf",
      "META-INF/manifest.xml", "Thumbnails/thumbnail.png", "Configurations2/",
    ]
    if !allowed.contains(name) || (name == "Configurations2/" && unpacked != 0) {
      raise Invalid("unsupported ODS package entry")
    }
    if names.contains(name) {
      raise Invalid("duplicate ZIP entry")
    }
    names.push(name)
    ods_zip_extra(data, p + 46 + name_len, extra_len)
    let local_start = ods_zip_size(data, p + 42)
    if local_start > cd_start - 30 ||
      ods_zip_u32(data, local_start) != 0x04034b50 {
      raise Invalid("invalid ZIP local header")
    }
    if ods_zip_u16(data, local_start + 4) != version ||
      ods_zip_u16(data, local_start + 6) != flags ||
      ods_zip_u16(data, local_start + 8) != compression ||
      ods_zip_u16(data, local_start + 26) != name_len {
      raise Invalid("ZIP local/directory mismatch")
    }
    let local_extra = ods_zip_u16(data, local_start + 28)
    let body = local_start + 30 + name_len + local_extra
    if body + packed > cd_start {
      raise Invalid("truncated ZIP entry")
    }
    if data[local_start + 30:local_start + 30 + name_len].to_owned() !=
      name_bytes {
      raise Invalid("ZIP local name mismatch")
    }
    ods_zip_extra(data, local_start + 30 + name_len, local_extra)
    let local_crc = ods_zip_u32(data, local_start + 14)
    let local_packed = ods_zip_size(data, local_start + 18)
    let local_unpacked = ods_zip_size(data, local_start + 22)
    let mut finish = body + packed
    if (flags & 8) == 0 {
      if local_crc != crc ||
        local_packed != packed ||
        local_unpacked != unpacked {
        raise Invalid("ZIP local size/CRC mismatch")
      }
    } else {
      if (local_crc != 0 && local_crc != crc) ||
        (local_packed != 0 && local_packed != packed) ||
        (local_unpacked != 0 && local_unpacked != unpacked) {
        raise Invalid("ZIP descriptor header mismatch")
      }
      // Accept both signed and unsigned ZIP32 data descriptors.
      let d = if ods_zip_u32(data, finish) == 0x08074b50 {
        finish + 4
      } else {
        finish
      }
      if d + 12 > cd_start ||
        ods_zip_u32(data, d) != crc ||
        ods_zip_size(data, d + 4) != packed ||
        ods_zip_size(data, d + 8) != unpacked {
        raise Invalid("invalid ZIP data descriptor")
      }
      finish = d + 12
    }
    for (a, b) in spans {
      if local_start < b && finish > a {
        raise Invalid("overlapping ZIP entries")
      }
    }
    spans.push((local_start, finish))
    covered = covered + finish - local_start
    let raw = data[body:body + packed].to_owned()
    let decoded = if compression == 0 {
      if packed != unpacked {
        raise Invalid("invalid stored ZIP size")
      }
      raw
    } else {
      ods_zip_inflate(raw, 4194304 - total)
    }
    if decoded.length() != unpacked {
      raise Invalid("forged ZIP uncompressed size")
    }
    if @checksum.crc32(decoded[:]).reinterpret_as_int() != crc {
      raise Invalid("ZIP CRC mismatch")
    }
    total = total + decoded.length()
    if name == "mimetype" {
      if compression != 0 ||
        local_start != 0 ||
        local_extra != 0 ||
        decoded != @utf8.encode(media_type[:]) {
        raise Invalid("invalid ODS mimetype")
      }
      mimetype = true
    } else if name == "content.xml" {
      content = Some(ods_zip_utf8(decoded))
    } else if name != "META-INF/manifest.xml" && name != "Configurations2/" {
      omitted.push(name)
    }
    p = next
  }
  if p != end || covered != cd_start || !mimetype {
    raise Invalid("invalid ODS ZIP structure")
  }
  match content {
    Some(xml) => xml
    None => raise Invalid("ODS content.xml missing")
  }
}
