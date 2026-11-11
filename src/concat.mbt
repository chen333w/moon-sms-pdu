///|
/// Capacity of one part, in the units TP-UDL uses for each alphabet.
///
/// With a six octet concatenation header the GSM 7-bit part holds 153 septets,
/// UCS-2 holds 67 code units and 8-bit payloads hold 134 octets.
pub fn part_capacity(encoding : Encoding) -> Int32 {
  match encoding {
    Gsm7 => 153
    Ucs2 => 134
    EightBit => 134
  }
}

///|
/// Capacity of a single, un-concatenated message.
pub fn single_capacity(encoding : Encoding) -> Int32 {
  match encoding {
    Gsm7 => 160
    Ucs2 => 140
    EightBit => 140
  }
}

///|
/// Splits text into parts that each fit a concatenation header.
///
/// Splitting happens on character boundaries, never inside an escaped GSM 7-bit
/// character, and never inside a surrogate pair.
pub fn split_text(
  text : StringView,
  encoding : Encoding,
) -> Array[String] raise SmsError {
  let limit = part_capacity(encoding)
  let parts : Array[String] = []
  let current = StringBuilder()
  let mut used = 0
  for ch in text {
    let cost = match encoding {
      Gsm7 => {
        guard gsm7_is_encodable(ch.to_string()) else {
          raise NotEncodable("U+" + ch.to_int().to_string())
        }
        if ch == '{' ||
          ch == '}' ||
          ch == '\\' ||
          ch == '[' ||
          ch == ']' ||
          ch == '~' ||
          ch == '|' ||
          ch == '^' ||
          ch == '€' {
          2
        } else {
          1
        }
      }
      // UCS-2 costs two octets per UTF-16 code unit.
      Ucs2 => ch.utf16_len() * 2
      EightBit => 1
    }
    if used + cost > limit {
      parts.push(current.to_string())
      current.reset()
      used = 0
    }
    current.write_char(ch)
    used = used + cost
  }
  if used > 0 || parts.is_empty() {
    parts.push(current.to_string())
  }
  parts
}

///|
/// Builds one submit per part, all sharing a reference and destination.
///
/// A message that fits in a single part is returned without a header, because
/// handsets render a one-part concatenated message oddly and some networks
/// bill it differently.
pub fn build_submits(
  destination : Address,
  text : String,
  reference : Int32,
  encoding? : Encoding,
) -> Array[SmsSubmit] raise SmsError {
  let encoding = encoding.unwrap_or(Gsm7)
  // A message that fits one part carries no header at all. Splitting first and
  // checking the part count second gets this backwards: a 160 septet message
  // is too long for a 153 septet concatenated part, so it would arrive as two
  // halves even though a single message would have held it.
  if fits_single(text, encoding) {
    return [SmsSubmit::new(destination, text, encoding~)]
  }
  let parts = split_text(text, encoding)
  guard parts.length() <= 255 else {
    raise InvalidField("message needs more than 255 parts")
  }
  let out : Array[SmsSubmit] = []
  for i, part in parts {
    out.push({
      ..SmsSubmit::new(destination, part, encoding~),
      concatenation: Some({
        reference: reference & 0xFF,
        total: parts.length(),
        sequence: i + 1,
      }),
    })
  }
  out
}

///|
/// Reassembles parts that belong to the same multi-part message.
///
/// Parts may arrive out of order and duplicated; both are handled. The result
/// is `None` until every sequence number is present.
pub fn assemble(parts : Array[SmsDeliver]) -> String? {
  if parts.is_empty() {
    return None
  }
  let first = parts[0].concatenation
  let total = match first {
    Some(c) => c.total
    None => return Some(parts[0].text)
  }
  let slots : Array[String?] = Array::make(total, None)
  for part in parts {
    match part.concatenation {
      Some(c) =>
        if c.total != total || c.sequence < 1 || c.sequence > total {
          return None
        } else if slots[c.sequence - 1] is None {
          slots[c.sequence - 1] = Some(part.text)
        }
      None => ()
    }
  }
  let buf = StringBuilder()
  for slot in slots {
    match slot {
      Some(text) => buf.write_string(text)
      None => return None
    }
  }
  Some(buf.to_string())
}

///|
/// Whether the text fits in one message with no user data header.
///
/// The limits are 160 septets for GSM 7-bit and 140 octets for the other two,
/// which is the number `length` reports and the number a handset sees.
pub fn fits_single(text : StringView, encoding : Encoding) -> Bool {
  match encoding {
    Gsm7 => {
      let septets = gsm7_septet_length(text)
      septets >= 0 && septets <= single_capacity(Gsm7)
    }
    // UCS-2 counts octets, two per UTF-16 code unit.
    Ucs2 => text.char_length() * 2 <= single_capacity(Ucs2)
    EightBit => text.char_length() <= single_capacity(EightBit)
  }
}
