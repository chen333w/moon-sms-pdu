///|
/// TP-PID: protocol identifier, 3GPP TS 23.040 §9.2.3.9.
///
/// The first two bits decide how the octet is read, so the three ranges below
/// are not interchangeable even when their numeric values overlap.
pub(all) enum ProtocolId {
  /// 00xxxxxx: the SMSC assigns a protocol.
  Assigned(Int32)
  /// 01xxxxxx: short message type, which decides how a handset routes it.
  MessageType(SmsMessageType)
  /// 10xxxxxx: telematic interworking, for messages that leave SMS.
  Telematic(TelematicDevice, TelematicSme?)
  /// 11xxxxxx: SC-specific protocol, taken from the SMSC's own numbering.
  ScSpecific(Int32)
} derive(Eq, @debug.Debug)

///|
/// The message types carried by an `01` TP-PID.
pub(all) enum SmsMessageType {
  /// 00000: a normal short message.
  ShortMessage
  /// 00001: replace the previous message of the same type, if any.
  ReplaceShortMessage
  /// 00010..: an SME-to-SME specific message.
  SmeSpecific(Int32)
  /// 00100: the SMSC is asking the SIM to start a data download.
  SimDataDownload
} derive(Eq, @debug.Debug)

///|
/// Telematic device a message is meant for, from the low bits of an `10` TP-PID.
pub(all) enum TelematicDevice {
  Implicit
  Teletex
  TelefaxGroup3
  TelefaxGroup4
  VoiceTelephony
  Ermes
  NationalPaging
  Videotex
  Telex
  MessageHandling
} derive(Eq, @debug.Debug)

///|
/// The optional second telematic device, used when a message goes between two
/// different kinds of terminal.
pub(all) enum TelematicSme {
  SmeA
  SmeB
} derive(Eq, @debug.Debug)

///|
/// Decodes a TP-PID octet.
///
/// The `01` group splits on bit 5: clear means the low five bits name a
/// message type, set means an SME-to-SME specific protocol.
pub fn decode_pid(pid : Int32) -> ProtocolId {
  let pid = pid & 0xFF
  match pid >> 6 {
    0 => Assigned(pid & 0x3F)
    1 =>
      if (pid & 0x20) != 0 {
        MessageType(SmeSpecific(pid & 0x1F))
      } else {
        MessageType(
          match pid & 0x1F {
            0 => ShortMessage
            1 => ReplaceShortMessage
            4 => SimDataDownload
            other => SmeSpecific(other)
          },
        )
      }
    2 => {
      let device = match (pid >> 2) & 0xF {
        0 => Implicit
        1 => Teletex
        2 => TelefaxGroup3
        3 => TelefaxGroup4
        4 => VoiceTelephony
        5 => Ermes
        6 => NationalPaging
        7 => Videotex
        9 => Telex
        10 => MessageHandling
        // Codes 8 and 11..15 are unassigned; Implicit is the neutral reading.
        _ => Implicit
      }
      let second = match pid & 0x3 {
        0 => None
        1 => Some(SmeA)
        2 => Some(SmeB)
        _ => None
      }
      Telematic(device, second)
    }
    _ => ScSpecific(pid & 0x3F)
  }
}

///|
/// Encodes a TP-PID octet.
pub fn encode_pid(pid : ProtocolId) -> Byte {
  match pid {
    Assigned(value) => (value & 0x3F).to_byte()
    MessageType(kind) =>
      (match kind {
        // The named types live in the low five bits with bit 5 clear.
        ShortMessage => 0x40
        ReplaceShortMessage => 0x41
        SimDataDownload => 0x44
        // SME-to-SME specific codes set bit 5.
        SmeSpecific(code) => 0x60 | (code & 0x1F)
      }).to_byte()
    Telematic(device, second) =>
      (0x80 |
      (
        (match device {
          Implicit => 0
          Teletex => 1
          TelefaxGroup3 => 2
          TelefaxGroup4 => 3
          VoiceTelephony => 4
          Ermes => 5
          NationalPaging => 6
          Videotex => 7
          Telex => 9
          MessageHandling => 10
        }) <<
        2
      ) |
      (match second {
        None => 0
        Some(SmeA) => 1
        Some(SmeB) => 2
      })).to_byte()
    ScSpecific(value) => (0xC0 | (value & 0x3F)).to_byte()
  }
}

///|
/// Whether the message is meant to leave SMS for another kind of terminal.
pub fn ProtocolId::is_interworking(self : ProtocolId) -> Bool {
  match self {
    Telematic(_, _) => true
    _ => false
  }
}

///|
pub impl Show for ProtocolId with fn to_string(self) {
  match self {
    Assigned(value) => "assigned (\{value})"
    MessageType(kind) =>
      match kind {
        ShortMessage => "short message"
        ReplaceShortMessage => "replace short message"
        SmeSpecific(code) => "sme specific (\{code})"
        SimDataDownload => "sim data download"
      }
    Telematic(device, second) =>
      "\{device}" +
      (match second {
        None => ""
        Some(SmeA) => " to sme-a"
        Some(SmeB) => " to sme-b"
      })
    ScSpecific(value) => "sc specific (\{value})"
  }
}

///|
pub impl Show for TelematicDevice with fn to_string(self) {
  match self {
    Implicit => "implicit"
    Teletex => "teletex"
    TelefaxGroup3 => "telefax group 3"
    TelefaxGroup4 => "telefax group 4"
    VoiceTelephony => "voice telephony"
    Ermes => "ermes"
    NationalPaging => "national paging"
    Videotex => "videotex"
    Telex => "telex"
    MessageHandling => "message handling"
  }
}

///|
pub impl Show for SmsMessageType with fn to_string(self) {
  match self {
    ShortMessage => "short message"
    ReplaceShortMessage => "replace short message"
    SmeSpecific(code) => "sme specific (\{code})"
    SimDataDownload => "sim data download"
  }
}
