// ODF 1.3 Part 3 section 6.1.2: raw XML whitespace is collapsed before
// explicit text:s/tab/line-break elements are expanded. One state spans all
// nested text:span elements, and is reset only at each paragraph boundary.

///|
priv struct ReadParagraph {
  output : StringBuilder
  mut units : Int32
  mut seen : Bool
  mut pending_space : Bool
}

///|
fn ReadParagraph::emit(
  self : ReadParagraph,
  text : String,
) -> Unit raise OdsError {
  if self.units > 32767 - text.length() {
    raise Invalid("expanded cell text exceeds budget")
  }
  self.output.write_string(text)
  self.units += text.length()
}

///|
fn ReadParagraph::boundary(self : ReadParagraph) -> Unit raise OdsError {
  if self.pending_space && self.seen {
    self.emit(" ")
  }
  self.pending_space = false
  self.seen = true
}

///|
fn ReadParagraph::append_parts(
  self : ReadParagraph,
  node : ReadElement,
) -> Unit raise OdsError {
  for part in node.parts {
    match part {
      ReadText(t) =>
        for c in t {
          if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
            self.pending_space = true
          } else {
            self.boundary()
            self.emit(c.to_string())
          }
        }
      ReadElement(e) =>
        if e.name == read_text + "span" {
          e.allowed([read_text + "style-name"])
          self.append_parts(e)
        } else if e.name == read_text + "s" {
          e.allowed([read_text + "c"])
          if !e.parts.is_empty() {
            raise Invalid("text:s must be empty")
          }
          let n = e.count(read_text, "c", 32767)
          self.boundary()
          if self.units > 32767 - n {
            raise Invalid("expanded cell text exceeds budget")
          }
          for _ in 0..<n {
            self.output.write_char(' ')
          }
          self.units += n
        } else if e.name == read_text + "tab" ||
          e.name == read_text + "line-break" {
          e.allowed([])
          if !e.parts.is_empty() {
            raise Invalid("text control must be empty")
          }
          self.boundary()
          self.emit(if e.name == read_text + "tab" { "\t" } else { "\n" })
        } else {
          raise Invalid("unsupported rich text, hyperlink, or embedded object")
        }
    }
  }
}
