///|
/// Parses hex into octets, skipping whitespace and `:` separators.
pub fn hex_to_octets(hex : StringView) -> Array[Byte] raise SmsError {
  let digits : Array[Int32] = []
  for ch in hex {
    match hex_digit_value(ch) {
      Some(value) => digits.push(value)
      None =>
        if ch != ' ' &&
          ch != '\t' &&
          ch != '\n' &&
          ch != '\r' &&
          ch != ':' &&
          ch != '-' {
          raise InvalidHex("unexpected character '\{ch}'")
        }
    }
  }
  guard digits.length() % 2 == 0 else {
    raise InvalidHex("odd number of hex digits")
  }
  let out : Array[Byte] = []
  let mut i = 0
  while i < digits.length() {
    out.push(((digits[i] << 4) | digits[i + 1]).to_byte())
    i = i + 2
  }
  out
}

///|
/// Renders octets as lowercase hex, no separators.
pub fn octets_to_hex(octets : ArrayView[Byte]) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for b in octets {
    let value = b.to_int()
    buf.write_char(digits.get_char(value >> 4).unwrap())
    buf.write_char(digits.get_char(value & 0xF).unwrap())
  }
  buf.to_string()
}

///|
/// Renders octets as uppercase hex with a space between each, the layout
/// `AT+CMGS` expects.
pub fn octets_to_hex_spaced(octets : ArrayView[Byte]) -> String {
  let buf = StringBuilder()
  for i, b in octets {
    if i > 0 {
      buf.write_char(' ')
    }
    let value = b.to_int()
    let digits = "0123456789ABCDEF"
    buf.write_char(digits.get_char(value >> 4).unwrap())
    buf.write_char(digits.get_char(value & 0xF).unwrap())
  }
  buf.to_string()
}

///|
fn hex_digit_value(ch : Char) -> Int32? {
  match ch {
    '0'..<='9' => Some(ch.to_int() - '0'.to_int())
    'a'..<='f' => Some(ch.to_int() - 'a'.to_int() + 10)
    'A'..<='F' => Some(ch.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// Decodes UTF-16BE octets into a string. A trailing odd octet is ignored, and
/// unpaired surrogates are replaced with U+FFFD rather than failing, because
/// real traffic contains them.
pub fn ucs2_to_utf8(octets : ArrayView[Byte]) -> String {
  let units : Array[UInt16] = []
  let mut i = 0
  while i + 1 < octets.length() {
    units.push(
      ((octets[i].to_int() << 8) | octets[i + 1].to_int())
      .reinterpret_as_uint()
      .to_uint16(),
    )
    i = i + 2
  }
  let out = StringBuilder()
  let mut k = 0
  while k < units.length() {
    let unit = units[k].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF && k + 1 < units.length() {
      let low = units[k + 1].to_int()
      if low >= 0xDC00 && low <= 0xDFFF {
        let code = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
        out.write_char(Int32::unsafe_to_char(code))
        k = k + 2
        continue
      }
    }
    if unit >= 0xD800 && unit <= 0xDFFF {
      out.write_char('\u{FFFD}')
    } else {
      out.write_char(Int32::unsafe_to_char(unit))
    }
    k = k + 1
  }
  out.to_string()
}

///|
/// Encodes text as UTF-16BE octets.
pub fn utf8_to_ucs2(text : StringView) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in text {
    let code = ch.to_int()
    if code >= 0x10000 {
      let adjusted = code - 0x10000
      let high = 0xD800 + (adjusted >> 10)
      let low = 0xDC00 + (adjusted & 0x3FF)
      out.push((high >> 8).to_byte())
      out.push((high & 0xFF).to_byte())
      out.push((low >> 8).to_byte())
      out.push((low & 0xFF).to_byte())
    } else {
      out.push((code >> 8).to_byte())
      out.push((code & 0xFF).to_byte())
    }
  }
  out
}

///|
/// Decodes octets as Latin-1. The 8-bit alphabet carries no charset of its own,
/// and Latin-1 round-trips every octet value without loss.
pub fn latin1_to_utf8(octets : ArrayView[Byte]) -> String {
  let buf = StringBuilder()
  for b in octets {
    buf.write_char(Int32::unsafe_to_char(b.to_int()))
  }
  buf.to_string()
}

///|
/// Encodes text as Latin-1 octets, rejecting code points above U+00FF.
pub fn utf8_to_latin1(text : StringView) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = []
  for ch in text {
    let code = ch.to_int()
    guard code <= 0xFF else {
      raise NotEncodable("not latin-1: U+" + code.to_string())
    }
    out.push(code.to_byte())
  }
  out
}

///|
/// Copies octets into `out` starting at `pos`, leaving the rest untouched.
pub fn write_bytes_at(
  out : Array[Byte],
  pos : Int32,
  src : ArrayView[Byte],
) -> Unit {
  for i, b in src {
    if pos + i < out.length() {
      out[pos + i] = b
    }
  }
}
