///|
/// The alphabet carrying TP-UD, derived from TP-DCS.
pub(all) enum Encoding {
  /// GSM 03.38 default alphabet, packed into septets.
  Gsm7
  /// Raw octets: ports, ringtones, OTA payloads.
  EightBit
  /// UTF-16BE, two octets per code unit.
  Ucs2
} derive(Eq, @debug.Debug)

///|
/// Decodes the alphabet from a TP-DCS octet, 3GPP TS 23.038 §4.
///
/// The coding groups handled here are the general data coding groups (bits 7..4
/// in 0000..0011 and 1111), which is what handsets and gateways emit in
/// practice. Message-waiting groups fall through to `Gsm7`.
pub fn encoding_of_dcs(dcs : Int) -> Encoding {
  let group = (dcs >> 4) & 0xF
  // Bit 5 flags compressed user data; the alphabet bits are its neighbours.
  let alphabet = (dcs >> 2) & 0x3
  if group <= 0x3 || group == 0xF {
    match alphabet {
      0 => Gsm7
      1 => EightBit
      2 => Ucs2
      _ => Gsm7
    }
  } else if group == 0xC || group == 0xD || group == 0xE {
    // Message waiting indication: the alphabet selector is in the low bit.
    if (dcs & 0x4) != 0 {
      Ucs2
    } else {
      Gsm7
    }
  } else {
    Gsm7
  }
}

///|
/// Builds a TP-DCS octet for an alphabet, using the general data coding group
/// with no message class.
pub fn dcs_of_encoding(encoding : Encoding) -> Byte {
  let alphabet = match encoding {
    Gsm7 => 0
    EightBit => 1
    Ucs2 => 2
  }
  // General data coding group: bits 3..2 select the alphabet, bits 1..0 the
  // message class. Leaving the class bits clear means "no class".
  (alphabet << 2).to_byte()
}
///|
pub impl Show for Encoding with fn to_string(self) {
  match self {
    Gsm7 => "GSM 7-bit"
    EightBit => "8-bit"
    Ucs2 => "UCS-2"
  }
}
