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
/// TP-DCS message class, 3GPP TS 23.038 §4.
///
/// Class 0 is the "flash" SMS: handsets display it straight away and usually
/// do not file it in the inbox. That distinction matters to anything that
/// counts messages, so it is surfaced rather than dropped.
pub(all) enum MessageClass {
  /// Class 0: display immediately, do not store.
  Flash
  /// Class 1: handsets treat it as handset-specific storage.
  Handset
  /// Class 2: SIM-specific storage.
  Sim
  /// Class 3: terminal equipment, typically forwarded over a serial link.
  Terminal
} derive(Eq, @debug.Debug)

///|
/// The kinds carried by a message-waiting indication group.
pub(all) enum MessageWaiting {
  Voicemail
  Fax
  Email
  Other
} derive(Eq, @debug.Debug)

///|
/// A decoded TP-DCS octet.
pub(all) struct DataCodingScheme {
  encoding : Encoding
  /// Set when the user data is compressed. The codec does not decompress:
  /// reporting the flag is more useful than silently returning garbage.
  compressed : Bool
  /// Absent when the SMSC left the class unset, which is the common case.
  class : MessageClass?
  /// Set by the message-waiting groups.
  waiting : MessageWaiting?
} derive(Eq, @debug.Debug)

///|
/// Decodes a TP-DCS octet, 3GPP TS 23.038 §4.
///
/// Only the two groups that carry user data are interpreted: the general data
/// coding groups (bits 7..6 clear) and the message-waiting groups (1100..1110).
/// The remaining groups describe pre-arranged coding the SMSC applies itself,
/// and fall back to GSM 7-bit.
pub fn decode_dcs(dcs : Int32) -> DataCodingScheme {
  let group = (dcs >> 4) & 0xF
  if group <= 0x3 {
    let class_present = (dcs & 0x10) != 0
    {
      encoding: match (dcs >> 2) & 0x3 {
        0 => Gsm7
        1 => EightBit
        2 => Ucs2
        // 11 is reserved; GSM 7-bit is what handsets assume.
        _ => Gsm7
      },
      compressed: (dcs & 0x20) != 0,
      class: if class_present {
        Some(
          match dcs & 0x3 {
            0 => Flash
            1 => Handset
            2 => Sim
            _ => Terminal
          },
        )
      } else {
        None
      },
      waiting: None,
    }
  } else if group == 0xC || group == 0xD || group == 0xE {
    {
      // In these groups bit 2 selects the alphabet and bits 1..0 the kind.
      encoding: if (dcs & 0x4) != 0 {
        Ucs2
      } else {
        Gsm7
      },
      compressed: false,
      class: None,
      waiting: Some(
        match dcs & 0x3 {
          0 => Voicemail
          1 => Fax
          2 => Email
          _ => Other
        },
      ),
    }
  } else if group == 0xF {
    {
      encoding: match (dcs >> 2) & 0x3 {
        0 => Gsm7
        1 => EightBit
        2 => Ucs2
        _ => Gsm7
      },
      compressed: false,
      // Group 1111 leaves bit 4 to the alphabet; there is no class field.
      class: None,
      waiting: None,
    }
  } else {
    { encoding: Gsm7, compressed: false, class: None, waiting: None, }
  }
}

///|
/// The alphabet of a TP-DCS octet, for callers that only need that.
pub fn encoding_of_dcs(dcs : Int32) -> Encoding {
  decode_dcs(dcs).encoding
}

///|
/// Builds a TP-DCS octet in the general data coding group.
pub fn encode_dcs(
  encoding : Encoding,
  class? : MessageClass,
  compressed? : Bool,
) -> Byte {
  let alphabet = match encoding {
    Gsm7 => 0
    EightBit => 1
    Ucs2 => 2
  }
  let class_bits = match class {
    None => 0
    Some(c) =>
      0x10 |
      (match c {
        Flash => 0
        Handset => 1
        Sim => 2
        Terminal => 3
      })
  }
  let compression_bit = if compressed.unwrap_or(false) { 0x20 } else { 0 }
  (compression_bit | class_bits | (alphabet << 2)).to_byte()
}

///|
/// Builds a TP-DCS octet for an alphabet alone, with no class.
pub fn dcs_of_encoding(encoding : Encoding) -> Byte {
  encode_dcs(encoding)
}

///|
pub impl Show for Encoding with fn to_string(self) {
  match self {
    Gsm7 => "GSM 7-bit"
    EightBit => "8-bit"
    Ucs2 => "UCS-2"
  }
}

///|
pub impl Show for MessageClass with fn to_string(self) {
  match self {
    Flash => "class 0 (flash)"
    Handset => "class 1 (handset)"
    Sim => "class 2 (sim)"
    Terminal => "class 3 (terminal)"
  }
}

///|
pub impl Show for MessageWaiting with fn to_string(self) {
  match self {
    Voicemail => "voicemail"
    Fax => "fax"
    Email => "email"
    Other => "other"
  }
}
