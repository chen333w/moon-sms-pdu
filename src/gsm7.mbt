///|
/// The GSM 03.38 default alphabet, indexed by septet value (0x00..0x7F).
let gsm7_default_table : Array[Char] = [
  '@', '£', '$', '¥', 'è', 'é', 'ù', 'ì', 'ò', 'Ç', '\n', 'Ø', 'ø', '\r',
  'Å', 'å', 'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ', 'Σ', 'Θ', 'Ξ', '\u{1b}',
  'Æ', 'æ', 'ß', 'É', ' ', '!', '"', '#', '¤', '%', '&', '\'', '(', ')', '*',
  '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':',
  ';', '<', '=', '>', '?', '¡', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
  'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  'Ä', 'Ö', 'Ñ', 'Ü', '§', '¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',
  'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
  'z', 'ä', 'ö', 'ñ', 'ü', 'à',
]

///|
/// Septet value of the escape introducer that switches to the extension table.
let gsm7_escape : Int32 = 0x1B

///|
/// Characters reachable through the escape, as (septet after 0x1B, character).
///
/// The extension table is sparse: only the positions below are assigned by
/// 3GPP TS 23.038 §6.2.1.1.
let gsm7_extension_table : Array[(Int32, Char)] = [
  (0, '@'),
  (10, '\f'),
  (13, '\r'),
  (17, '_'),
  (20, '^'),
  (30, '{'),
  (40, '|'),
  (41, '}'),
  (47, '\\'),
  (49, '['),
  (50, '~'),
  (57, ']'),
  (60, '€'),
]

///|
/// Reverse lookup: character to (septet, escaped).
fn gsm7_lookup(ch : Char) -> (Int32, Bool)? {
  for i, c in gsm7_default_table {
    if c == ch && i != gsm7_escape {
      return Some((i, false))
    }
  }
  for pair in gsm7_extension_table {
    let (k, v) = pair
    if v == ch {
      return Some((k, true))
    }
  }
  None
}

///|
/// True when every character of `text` exists in the GSM 03.38 alphabet.
pub fn gsm7_is_encodable(text : StringView) -> Bool {
  for ch in text {
    if gsm7_lookup(ch) is None {
      return false
    }
  }
  true
}

///|
/// Septets `text` occupies, counting an escaped character as two.
/// Returns -1 when the text is not representable.
pub fn gsm7_septet_length(text : StringView) -> Int32 {
  let mut n = 0
  for ch in text {
    match gsm7_lookup(ch) {
      Some((_, escaped)) => n = n + (if escaped { 2 } else { 1 })
      None => return -1
    }
  }
  n
}

///|
/// Encodes text to septets, one value per entry in 0..127.
pub fn gsm7_to_septets(text : StringView) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = []
  for ch in text {
    match gsm7_lookup(ch) {
      Some((value, escaped)) => {
        if escaped {
          out.push(gsm7_escape.to_byte())
        }
        out.push(value.to_byte())
      }
      None => raise NotEncodable("U+" + hex4(ch.to_int()))
    }
  }
  out
}

///|
/// Decodes septets back to text.
///
/// A trailing escape with nothing after it is dropped. An escape followed by a
/// code the extension table does not define falls back to the default table.
pub fn gsm7_from_septets(septets : ArrayView[Byte]) -> String {
  let buf = StringBuilder()
  let mut i = 0
  while i < septets.length() {
    let value = septets[i].to_int()
    if value == gsm7_escape {
      if i + 1 >= septets.length() {
        break
      }
      let next = septets[i + 1].to_int()
      let mut mapped = '\u{0}'
      for pair in gsm7_extension_table {
        if pair.0 == next {
          mapped = pair.1
        }
      }
      if mapped == '\u{0}' {
        buf.write_char(gsm7_default_table[next])
      } else {
        buf.write_char(mapped)
      }
      i = i + 2
      continue
    }
    buf.write_char(gsm7_default_table[value])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Packs septets into octets. `fill_bits` shifts the whole stream left so the
/// user data can start on an octet boundary behind a user data header.
pub fn gsm7_pack(septets : ArrayView[Byte], fill_bits : Int32) -> Array[Byte] {
  let total_bits = fill_bits + 7 * septets.length()
  let out : Array[Byte] = Array::make((total_bits + 7) / 8, b'\x00')
  write_septets(out, 0, septets, fill_bits)
  out
}

///|
/// Writes septets into `out` starting at the given bit position. Bits already
/// present in `out` are preserved, which is how a user data header and its text
/// share one septet stream.
pub fn write_septets(
  out : Array[Byte],
  base : Int32,
  septets : ArrayView[Byte],
  start_bit : Int32,
) -> Unit {
  for i, s in septets {
    let bit_pos = start_bit + 7 * i
    let byte_pos = base + bit_pos / 8
    let offset = bit_pos % 8
    if byte_pos >= out.length() {
      break
    }
    out[byte_pos] = (out[byte_pos].to_int() | ((s.to_int() & 0x7F) << offset)).to_byte()
    if offset > 1 && byte_pos + 1 < out.length() {
      out[byte_pos + 1] = (out[byte_pos + 1].to_int() |
      ((s.to_int() & 0x7F) >> (8 - offset))).to_byte()
    }
  }
}

///|
/// Number of fill bits needed to bring a user data header of `octets` octets up
/// to the next septet boundary.
pub fn header_fill_bits(octets : Int32) -> Int32 {
  (7 - octets * 8 % 7) % 7
}

///|
/// Septets a header of `octets` octets occupies once padded.
pub fn header_septets(octets : Int32) -> Int32 {
  (octets * 8 + header_fill_bits(octets)) / 7
}

///|
/// Unpacks octets into at most `septet_count` septets, skipping `fill_bits`
/// leading padding bits.
pub fn gsm7_unpack(
  octets : ArrayView[Byte],
  septet_count : Int32,
  fill_bits : Int32,
) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut n = 0
  while n < septet_count {
    let bit_pos = fill_bits + 7 * n
    let byte_pos = bit_pos / 8
    if byte_pos >= octets.length() {
      break
    }
    let offset = bit_pos % 8
    let mut value = octets[byte_pos].to_int() >> offset
    if offset > 1 && byte_pos + 1 < octets.length() {
      value = value | (octets[byte_pos + 1].to_int() << (8 - offset))
    }
    out.push((value & 0x7F).to_byte())
    n = n + 1
  }
  out
}

///|
/// Number of septets that fit in `octet_count` octets after `fill_bits`
/// padding.
pub fn gsm7_fit_septets(octet_count : Int32, fill_bits : Int32) -> Int32 {
  if octet_count * 8 <= fill_bits {
    return 0
  }
  (octet_count * 8 - fill_bits) / 7
}

///|
fn hex4(value : Int32) -> String {
  let digits = "0123456789ABCDEF"
  let mut out = ""
  let mut shift = 12
  while shift >= 0 {
    out = out + digits.get_char((value >> shift) & 0xF).unwrap().to_string()
    shift = shift - 4
  }
  out
}
