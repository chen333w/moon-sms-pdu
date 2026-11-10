///|
/// Numbering plan (type-of-address bits 0..3), 3GPP TS 23.040 §9.1.2.5.
pub(all) enum NumberingPlan {
  Unknown
  Isdn
  Data
  Telex
  NationalNumberingPlan
  PrivateNumberingPlan
  Ermes
  Reserved
} derive(Eq, @debug.Debug)

///|
/// Type of number (type-of-address bits 4..6).
pub(all) enum NumberType {
  Unknown
  International
  National
  NetworkSpecific
  SubscriberNumber
  Alphanumeric
  Abbreviated
  Reserved
} derive(Eq, @debug.Debug)

///|
/// A TP address: a phone number, or an alphanumeric string for the case where
/// a sender has a name instead of a number.
pub(all) enum Address {
  /// A dialable number with its plan and type.
  Number(NumberType, NumberingPlan, String)
  /// GSM 03.38 packed text, used by gateways and by sender headers.
  Alphanumeric(String)
} derive(Eq, @debug.Debug)

///|
fn nibble_to_digit(n : Int32) -> Char {
  match n {
    0xA => '*'
    0xB => '#'
    0xC => 'a'
    0xD => 'b'
    0xE => 'c'
    _ => Int32::unsafe_to_char('0'.to_int() + n)
  }
}

///|
fn digit_to_nibble(ch : Char) -> Int32? {
  match ch {
    '0'..<='9' => Some(ch.to_int() - '0'.to_int())
    '*' => Some(0xA)
    '#' => Some(0xB)
    'a' => Some(0xC)
    'b' => Some(0xD)
    'c' => Some(0xE)
    _ => None
  }
}

///|
/// Encodes a digit string as BCD, low nibble first, padded with 0xF.
fn encode_number_digits(digits : StringView) -> Array[Byte] raise SmsError {
  // TP-DA is one octet of semi-octets, so twenty digits is the ceiling. A
  // longer number would encode its length into a byte the receiver reads as
  // something else.
  guard digits.char_length() <= 20 else {
    raise InvalidField("address longer than twenty digits")
  }
  let out : Array[Byte] = []
  let chars = digits.to_array()
  let mut i = 0
  while i < chars.length() {
    let low = digit_to_nibble(chars[i])
    guard low is Some(low) else {
      raise InvalidField("address digit '\{chars[i]}'")
    }
    let high = if i + 1 < chars.length() {
      guard digit_to_nibble(chars[i + 1]) is Some(h) else {
        raise InvalidField("address digit '\{chars[i + 1]}'")
      }
      h
    } else {
      0xF
    }
    out.push((low | (high << 4)).to_byte())
    i = i + 2
  }
  out
}

///|
/// Semi-octet count of a digit string.
fn digit_count(digits : StringView) -> Int32 {
  digits.char_length()
}

///|
/// Serialises an address as the type-of-address byte plus the digits.
pub fn Address::to_octets(self : Address) -> Array[Byte] raise SmsError {
  match self {
    Number(type_, plan, digits) => {
      guard type_ != Alphanumeric && type_ != Reserved else {
        raise InvalidField("number type for a BCD address")
      }
      let toa = (0x80 |
      (number_type_bits(type_) << 4) |
      numbering_plan_bits(plan)).to_byte()
      let body = encode_number_digits(digits)
      let out : Array[Byte] = [digit_count(digits).to_byte(), toa]
      out.append(body)
      out
    }
    Alphanumeric(text) => {
      let septets = gsm7_to_septets(text)
      let octets = gsm7_pack(septets, 0)
      let toa = (0x80 | (number_type_bits(Alphanumeric) << 4)).to_byte()
      let out : Array[Byte] = [septets.length().to_byte(), toa]
      out.append(octets)
      out
    }
  }
}

///|
fn number_type_bits(type_ : NumberType) -> Int32 {
  match type_ {
    Unknown => 0
    International => 1
    National => 2
    NetworkSpecific => 3
    SubscriberNumber => 4
    Alphanumeric => 5
    Abbreviated => 6
    Reserved => 7
  }
}

///|
fn number_type_of_bits(bits : Int32) -> NumberType {
  match bits {
    0 => Unknown
    1 => International
    2 => National
    3 => NetworkSpecific
    4 => SubscriberNumber
    5 => Alphanumeric
    6 => Abbreviated
    _ => Reserved
  }
}

///|
fn numbering_plan_bits(plan : NumberingPlan) -> Int32 {
  match plan {
    Unknown => 0
    Isdn => 1
    Data => 3
    Telex => 4
    NationalNumberingPlan => 8
    PrivateNumberingPlan => 9
    Ermes => 10
    Reserved => 15
  }
}

///|
fn numbering_plan_of_bits(bits : Int32) -> NumberingPlan {
  match bits {
    1 => Isdn
    3 => Data
    4 => Telex
    8 => NationalNumberingPlan
    9 => PrivateNumberingPlan
    10 => Ermes
    15 => Reserved
    _ => Unknown
  }
}

///|
/// Parses an address field starting at `pos`. Returns the address and the
/// offset just past it.
pub fn read_address(
  octets : ArrayView[Byte],
  pos : Int32,
) -> (Address, Int32) raise SmsError {
  guard pos < octets.length() else { raise Truncated("address length") }
  let count = octets[pos].to_int()
  guard pos + 1 < octets.length() else { raise Truncated("address type") }
  let toa = octets[pos + 1].to_int()
  let type_ = number_type_of_bits((toa >> 4) & 0x7)
  let plan = numbering_plan_of_bits(toa & 0xF)
  if type_ == Alphanumeric {
    // For an alphanumeric address the length octet counts septets, not
    // semi-octets, and the body is a packed GSM 7-bit string.
    let octet_len = (count * 7 + 7) / 8
    guard pos + 2 + octet_len <= octets.length() else {
      raise Truncated("alphanumeric address")
    }
    let septets = gsm7_unpack(octets[pos + 2:pos + 2 + octet_len], count, 0)
    return (Alphanumeric(gsm7_from_septets(septets)), pos + 2 + octet_len)
  }
  let octet_len = (count + 1) / 2
  guard pos + 2 + octet_len <= octets.length() else {
    raise Truncated("address digits")
  }
  let buf = StringBuilder()
  for i = 0; i < count; i = i + 1 {
    let byte = octets[pos + 2 + i / 2].to_int()
    let nibble = if i % 2 == 0 { byte & 0xF } else { (byte >> 4) & 0xF }
    buf.write_char(nibble_to_digit(nibble))
  }
  (Number(type_, plan, buf.to_string()), pos + 2 + octet_len)
}

///|
/// Picks a type and plan for a dialled number that arrived without a `+`.
///
/// A leading `00` is the international access code and a leading `0` a national
/// trunk prefix, which is how modems and gateways expect raw digits to be
/// classified. Anything else is treated as a national subscriber number, since
/// assuming `Unknown` makes several networks reject the SUBMIT.
pub fn classify_digits(
  digits : StringView,
) -> (NumberType, NumberingPlan, String) {
  if digits.has_prefix("00") && digits.char_length() > 4 {
    return (International, Isdn, digits[2:].to_owned())
  }
  if digits.has_prefix("0") && digits.char_length() > 2 {
    return (National, Isdn, digits[1:].to_owned())
  }
  (National, Isdn, digits.to_owned())
}

///|
/// Formats an address for display: international numbers get a leading `+`.
pub fn Address::to_string_display(self : Address) -> String {
  match self {
    Number(type_, _, digits) =>
      if type_ == International {
        "+" + digits
      } else {
        digits
      }
    Alphanumeric(text) => text
  }
}

///|
pub impl Show for Address with fn to_string(self) {
  match self {
    Number(type_, plan, digits) => "\{type_}/\{plan}: \{digits}"
    Alphanumeric(text) => "alphanumeric: \{text}"
  }
}

///|
pub impl Show for NumberType with fn to_string(self) {
  match self {
    Unknown => "unknown"
    International => "international"
    National => "national"
    NetworkSpecific => "network"
    SubscriberNumber => "subscriber"
    Alphanumeric => "alphanumeric"
    Abbreviated => "abbreviated"
    Reserved => "reserved"
  }
}

///|
pub impl Show for NumberingPlan with fn to_string(self) {
  match self {
    Unknown => "unknown"
    Isdn => "isdn"
    Data => "data"
    Telex => "telex"
    NationalNumberingPlan => "national-plan"
    PrivateNumberingPlan => "private-plan"
    Ermes => "ermes"
    Reserved => "reserved"
  }
}
