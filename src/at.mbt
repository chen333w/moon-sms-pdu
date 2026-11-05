///|
/// Splits a `+CMGL` style response line into its fields.
///
/// A modem answers with lines like
/// `+CMGL: 1,0,,24` followed by the PDU on the next line, or with every field
/// on one comma-separated line depending on how `AT+CMGF` was last set. Quoted
/// fields may contain commas, so splitting on `,` alone is not enough.
pub fn split_at_fields(line : StringView) -> Array[String] {
  let fields : Array[String] = []
  let current = StringBuilder()
  let mut in_quotes = false
  for ch in line {
    if ch == '"' {
      in_quotes = !in_quotes
    } else if ch == ',' && !in_quotes {
      fields.push(current.to_string())
      current.reset()
    } else {
      current.write_char(ch)
    }
  }
  fields.push(current.to_string())
  fields
}

///|
/// Command that switches the modem to PDU mode.
///
/// Every function in this file assumes PDU mode. In text mode the modem does
/// its own encoding, and the whole point of carrying a codec is to not depend
/// on that.
pub fn at_pdu_mode() -> String {
  "AT+CMGF=0"
}

///|
/// Command that asks the modem to send a submit PDU. The length is the TPDU
/// length in octets, which is the full PDU minus the SMSC prefix.
pub fn at_send(pdu : ArrayView[Byte]) -> String raise SmsError {
  let length = tpdu_length(pdu)
  "AT+CMGS=\{length}\r" + octets_to_hex(pdu) + "\u{1a}"
}

///|
/// Length a modem expects after `AT+CMGS=`, which excludes the SMSC address.
pub fn tpdu_length(pdu : ArrayView[Byte]) -> Int32 raise SmsError {
  guard pdu.length() >= 1 else { raise Truncated("pdu") }
  let smsc_length = pdu[0].to_int()
  let prefix = 1 + smsc_length
  guard prefix <= pdu.length() else { raise Truncated("smsc prefix") }
  pdu.length() - prefix
}

///|
/// Command that lists stored messages in PDU mode.
pub fn at_list(stat? : String) -> String {
  match stat {
    Some(stat) => "AT+CMGL=\"" + stat + "\""
    None => "AT+CMGL=4"
  }
}

///|
/// Command that reads one stored message by index.
pub fn at_read(index : Int32) -> String {
  "AT+CMGR=\{index}"
}

///|
/// Command that deletes one stored message by index.
pub fn at_delete(index : Int32) -> String {
  "AT+CMGD=\{index}"
}

///|
/// Command that sends a USSD string.
pub fn at_ussd(code : String) -> String {
  "AT+CUSD=1,\"" + code + "\",15"
}

///|
/// A message the modem reported, with the slot it occupies.
pub(all) struct ModemMessage {
  index : Int32
  /// The `stat` field the modem used, such as `REC UNREAD`.
  status : String
  pdu : Pdu
} derive(Eq, @debug.Debug)

///|
/// Reads a `+CMGL` response.
///
/// Modems disagree on whitespace and on whether the PDU shares the line with
/// the header, so both shapes are accepted. Lines that are not part of a
/// message are skipped instead of failing the whole read: a response often
/// carries a trailing `OK` or an echo of the command.
pub fn parse_cmgl(response : StringView) -> Array[ModemMessage] raise SmsError {
  let messages : Array[ModemMessage] = []
  let mut pending_index = -1
  let mut pending_status = ""
  let mut has_pending = false
  for raw_line in response.split("\n") {
    let line = raw_line.to_owned().trim()
    if line.is_empty() {
      continue
    }
    if line.has_prefix("+CMGL:") {
      let fields = split_at_fields(line[6:].to_owned())
      pending_index = match fields.get(0) {
        Some(text) => parse_int_or(text, -1)
        None => -1
      }
      pending_status = match fields.get(1) {
        Some(text) => text
        None => ""
      }
      // The fourth field is the TPDU length, not the PDU itself, so the PDU
      // always arrives on a following line.
      has_pending = true
      continue
    }
    if has_pending && looks_like_hex(line) {
      messages.push({
        index: pending_index,
        status: pending_status,
        pdu: parse_pdu(line),
      })
      has_pending = false
    }
  }
  messages
}

///|
fn parse_int_or(text : StringView, fallback : Int32) -> Int32 {
  let parsed = Some(@strconv.parse_int(text.trim())) catch { _ => None }
  parsed.unwrap_or(fallback)
}

///|
fn looks_like_hex(text : StringView) -> Bool {
  if text.length() < 2 {
    return false
  }
  if text.length() % 2 != 0 {
    return false
  }
  for ch in text {
    match ch {
      '0'..<='9' | 'a'..<='f' | 'A'..<='F' => ()
      _ => return false
    }
  }
  true
}

///|
/// Builds the whole `AT+CMGS` conversation for one PDU.
///
/// Returns the lines to write in order. The last line ends with Ctrl-Z, which
/// is what actually tells the modem the message is finished; sending it early
/// truncates the PDU.
pub fn at_send_sequence(pdu : ArrayView[Byte]) -> Array[String] raise SmsError {
  [at_pdu_mode(), "AT+CSCS=\"GSM\"", at_send(pdu)]
}
