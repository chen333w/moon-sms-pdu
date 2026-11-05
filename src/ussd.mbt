///|
/// A USSD message as carried over GSM 04.90 / 03.40 TP-UD.
///
/// USSD shares the SMS transport but not the message layout. The first octet is
/// a data coding scheme, then a string of the 0x42 characters used by phone
/// menus (`*`, `#`, digits). Radio-layer baseband traces show the body as
/// `AA`-marked 7-bit data, which is why it lands in the same codec.
pub(all) struct UssdMessage {
  /// The text the network or handset wants to show, without the menu framing.
  text : String
  encoding : Encoding
  /// Set when the equipment asked the network to stop an in-progress session.
  abort : Bool
}

///|
/// Decodes a USSD string as found in TP-UD.
///
/// The body may or may not carry the leading DCS octet: some modems hand it
/// over after the coding scheme has already been moved into a separate field.
/// `has_dcs` says which layout is in front of you.
pub fn UssdMessage::parse(
  octets : ArrayView[Byte],
  has_dcs? : Bool,
) -> UssdMessage raise SmsError {
  let has_dcs = has_dcs.unwrap_or(true)
  guard octets.length() > 0 else { raise Truncated("ussd") }
  let mut pos = 0
  let encoding = if has_dcs {
    pos = 1
    encoding_of_dcs(octets[0].to_int())
  } else {
    Gsm7
  }
  let body = octets[pos:]
  let text = match encoding {
    Gsm7 => {
      let septets = gsm7_unpack(body, gsm7_fit_septets(body.length(), 0), 0)
      gsm7_from_septets(septets)
    }
    Ucs2 => ucs2_to_utf8(body)
    EightBit => latin1_to_utf8(body)
  }
  { text, encoding, abort: false, }
}

///|
/// Encodes a USSD body, DCS octet included.
pub fn UssdMessage::to_octets(self : UssdMessage) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = [dcs_of_encoding(self.encoding)]
  match self.encoding {
    Gsm7 => out.append(gsm7_pack(gsm7_to_septets(self.text), 0))
    Ucs2 => out.append(utf8_to_ucs2(self.text))
    EightBit => out.append(utf8_to_latin1(self.text))
  }
  out
}

///|
/// Builds a USSD message, choosing UCS-2 when the text leaves the GSM alphabet.
pub fn UssdMessage::new(text : String) -> UssdMessage {
  {
    text,
    encoding: if gsm7_is_encodable(text) {
      Gsm7
    } else {
      Ucs2
    },
    abort: false,
  }
}

///|
pub impl Show for UssdMessage with fn to_string(self) {
  self.text
}
