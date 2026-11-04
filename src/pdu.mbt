///|
/// TP-VP: how long the SMSC should keep trying.
pub(all) enum ValidityPeriod {
  /// Let the SMSC apply its own default.
  Default
  /// Duration in minutes, expressed in the relative format.
  Relative(Int)
  /// Raw relative octet, kept verbatim so a decode can re-encode byte for byte.
  RelativeRaw(Int)
  /// Absolute timestamp.
  Absolute(Timestamp)
} derive(Eq, @debug.Debug)

///|
/// TP-ST of a status report.
pub(all) enum StatusReportStatus {
  /// 0x00: delivered.
  Delivered
  /// 0x01..0x1F: still being retried.
  TemporaryError(Int)
  /// 0x20..0x3F: retries exhausted.
  PermanentError(Int)
  /// 0x40..0x7F: temporary failure of a type the SMSC did not classify.
  TemporaryUnknown(Int)
  /// 0x80..: codes the standard leaves to the protocol, kept raw.
  Other(Int)
} derive(Eq, @debug.Debug)

///|
/// An SMS-SUBMIT: a message on its way to the SMSC.
pub(all) struct SmsSubmit {
  message_reference : Int
  destination : Address
  validity : ValidityPeriod
  encoding : Encoding
  text : String
  concatenation : Concatenation?
  /// Raw TP-UD used when `encoding` is `EightBit`.
  payload : Array[Byte]
  request_status_report : Bool
  reply_path : Bool
  reject_duplicates : Bool
  /// SMSC to relay through, when the caller wants to override the default.
  smsc : Address?
} derive(Eq, @debug.Debug)

///|
/// An SMS-DELIVER: a message the SMSC handed to the handset.
pub(all) struct SmsDeliver {
  originating : Address
  service_center : Address?
  timestamp : Timestamp
  encoding : Encoding
  text : String
  payload : Array[Byte]
  header : UserDataHeader?
  concatenation : Concatenation?
  /// False means the SMSC still has more messages queued.
  no_more_messages : Bool
  status_report_indication : Bool
  reply_path : Bool
} derive(Eq, @debug.Debug)

///|
/// An SMS-STATUS-REPORT.
pub(all) struct StatusReport {
  message_reference : Int
  recipient : Address
  service_center : Address?
  timestamp : Timestamp
  discharge_time : Timestamp
  status : StatusReportStatus
  no_more_messages : Bool
  reply_path : Bool
} derive(Eq, @debug.Debug)

///|
/// Any TP-DU this codec can read.
pub(all) enum Pdu {
  Submit(SmsSubmit)
  Deliver(SmsDeliver)
  StatusReport(StatusReport)
} derive(Eq, @debug.Debug)

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

///|
/// Reads a PDU from hex. Whitespace and `:` separators are ignored, so the
/// output of `AT+CMGL` can be pasted directly.
pub fn parse_pdu(hex : StringView) -> Pdu raise SmsError {
  parse_octets(hex_to_octets(hex))
}

///|
/// Reads a PDU from octets, SMSC prefix included.
pub fn parse_octets(octets : ArrayView[Byte]) -> Pdu raise SmsError {
  let (smsc, pos) = read_smsc(octets, 0)
  guard pos < octets.length() else { raise Truncated("tpdu type") }
  let first = octets[pos].to_int()
  match first & 0x3 {
    0 => Deliver(decode_deliver(octets, pos + 1, first, smsc))
    1 => Submit(decode_submit(octets, pos + 1, first, smsc))
    2 => StatusReport(decode_status_report(octets, pos + 1, first, smsc))
    _ => raise InvalidField("reserved tpdu type")
  }
}

///|
/// Reads the SMSC address that prefixes every PDU.
fn read_smsc(octets : ArrayView[Byte], pos : Int) -> (Address?, Int) raise SmsError {
  guard pos < octets.length() else { raise Truncated("smsc length") }
  let length = octets[pos].to_int()
  if length == 0 {
    return (None, pos + 1)
  }
  guard length >= 1 else { raise InvalidField("smsc length") }
  guard pos + 1 + length <= octets.length() else { raise Truncated("smsc") }
  let toa = octets[pos + 1].to_int()
  let type_ = number_type_of_bits((toa >> 4) & 0x7)
  let plan = numbering_plan_of_bits(toa & 0xF)
  let digit_semi = (length - 1) * 2
  let buf = StringBuilder()
  for i = 0; i < digit_semi; i = i + 1 {
    let byte = octets[pos + 2 + i / 2].to_int()
    let nibble = if i % 2 == 0 { byte & 0xF } else { (byte >> 4) & 0xF }
    let is_padding = i == digit_semi - 1 && nibble == 0xF
    if not(is_padding) {
      buf.write_char(nibble_to_digit(nibble))
    }
  }
  (Some(Number(type_, plan, buf.to_string())), pos + 1 + length)
}

///|
fn decode_deliver(
  octets : ArrayView[Byte],
  start : Int,
  first : Int,
  smsc : Address?,
) -> SmsDeliver raise SmsError {
  // TP-UDHI is bit 6. Bit 5 of the deliver type octet is TP-SRI, a different
  // flag, so it must not be read as header presence.
  let has_udh = (first & 0x40) != 0
  let (originating, pos) = read_address(octets, start)
  let pid = need(octets, pos, "tp-pid")
  let dcs = need(octets, pos + 1, "tp-dcs")
  let timestamp = read_timestamp(octets, pos + 2)
  let udl = need(octets, pos + 9, "tp-udl")
  let encoding = encoding_of_dcs(dcs)
  let (text, payload, header) = decode_user_data(
    octets, pos + 10, udl, has_udh, encoding,
  )
  let _ = pid
  {
    originating,
    service_center: smsc,
    timestamp,
    encoding,
    text,
    payload,
    header,
    concatenation: match header {
      Some(h) => h.concatenation()
      None => None
    },
    no_more_messages: (first & 0x04) != 0,
    status_report_indication: (first & 0x20) != 0,
    reply_path: (first & 0x80) != 0,
  }
}

///|
fn decode_submit(
  octets : ArrayView[Byte],
  start : Int,
  first : Int,
  smsc : Address?,
) -> SmsSubmit raise SmsError {
  let has_udh = (first & 0x40) != 0
  let vpf = (first >> 3) & 0x3
  let message_reference = need(octets, start, "tp-mr")
  let (destination, address_end) = read_address(octets, start + 1)
  let mut pos = address_end
  let _ = need(octets, pos, "tp-pid")
  let dcs = need(octets, pos + 1, "tp-dcs")
  pos = pos + 2
  let validity = match vpf {
    0 => Default
    1 | 2 => {
      let raw = need(octets, pos, "tp-vp")
      pos = pos + 1
      if vpf == 2 {
        RelativeRaw(raw)
      } else {
        decode_relative_validity(raw)
      }
    }
    _ => {
      let stamp = read_timestamp(octets, pos)
      pos = pos + 7
      Absolute(stamp)
    }
  }
  let udl = need(octets, pos, "tp-udl")
  let encoding = encoding_of_dcs(dcs)
  let (text, payload, header) = decode_user_data(
    octets, pos + 1, udl, has_udh, encoding,
  )
  {
    message_reference,
    destination,
    validity,
    encoding,
    text,
    concatenation: match header {
      Some(h) => h.concatenation()
      None => None
    },
    payload,
    request_status_report: (first & 0x20) != 0,
    reply_path: (first & 0x80) != 0,
    reject_duplicates: (first & 0x04) != 0,
    smsc,
  }
}

///|
fn decode_status_report(
  octets : ArrayView[Byte],
  start : Int,
  first : Int,
  smsc : Address?,
) -> StatusReport raise SmsError {
  let message_reference = need(octets, start, "tp-mr")
  let (recipient, pos) = read_address(octets, start + 1)
  let timestamp = read_timestamp(octets, pos)
  let discharge_time = read_timestamp(octets, pos + 7)
  let status_code = need(octets, pos + 14, "tp-st")
  {
    message_reference,
    recipient,
    service_center: smsc,
    timestamp,
    discharge_time,
    status: status_of_code(status_code),
    no_more_messages: (first & 0x04) != 0,
    reply_path: (first & 0x80) != 0,
  }
}

///|
fn status_of_code(code : Int) -> StatusReportStatus {
  if code == 0 {
    Delivered
  } else if code <= 0x1F {
    TemporaryError(code)
  } else if code <= 0x3F {
    PermanentError(code)
  } else if code <= 0x7F {
    TemporaryUnknown(code)
  } else {
    Other(code)
  }
}

///|
/// Decodes TP-UD into text, raw payload and the optional header.
fn decode_user_data(
  octets : ArrayView[Byte],
  pos : Int,
  udl : Int,
  has_udh : Bool,
  encoding : Encoding,
) -> (String, Array[Byte], UserDataHeader?) raise SmsError {
  if encoding == Gsm7 {
    if has_udh {
      // With a header, TP-UDL counts whole octets for the header but septets
      // for the text behind it, so the two segments are unpacked separately.
      guard pos < octets.length() else { raise Truncated("user data header") }
      let header_octets = octets[pos].to_int() + 1
      let body_septets = udl - header_septets(header_octets)
      let body_octets = (body_septets * 7 + 7) / 8
      guard pos + header_octets + body_octets <= octets.length() else {
        raise BadLength("gsm7 user data overruns the pdu")
      }
      let raw_header = octets[pos:pos + header_octets]
      let (header, consumed) = UserDataHeader::parse(raw_header)
      let septets = gsm7_unpack(
        octets[pos + consumed:pos + header_octets + body_octets], body_septets,
        0,
      )
      (gsm7_from_septets(septets), [], Some(header))
    } else {
      // TP-UDL counts septets, so the octets holding them are derived from it.
      let octet_len = (udl * 7 + 7) / 8
      guard pos + octet_len <= octets.length() else {
        raise BadLength("gsm7 user data overruns the pdu")
      }
      let septets = gsm7_unpack(octets[pos:pos + octet_len], udl, 0)
      (gsm7_from_septets(septets), [], None)
    }
  } else {
    guard pos + udl <= octets.length() else {
      raise BadLength("user data overruns the pdu")
    }
    let raw = octets[pos:pos + udl]
    if has_udh {
      let (header, consumed) = UserDataHeader::parse(raw)
      let body = raw[consumed:]
      let text = match encoding {
        Ucs2 => ucs2_to_utf8(body)
        _ => latin1_to_utf8(body)
      }
      (text, body.to_owned(), Some(header))
    } else {
      let text = match encoding {
        Ucs2 => ucs2_to_utf8(raw)
        _ => latin1_to_utf8(raw)
      }
      (text, raw.to_owned(), None)
    }
  }
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

///|
/// Builds a submit for the common case: one part, GSM 7-bit, default validity.
pub fn SmsSubmit::new(
  destination : Address,
  text : String,
  encoding? : Encoding,
) -> SmsSubmit {
  {
    message_reference: 0,
    destination,
    validity: Default,
    encoding: encoding.unwrap_or(Gsm7),
    text,
    concatenation: None,
    payload: [],
    request_status_report: false,
    reply_path: false,
    reject_duplicates: false,
    smsc: None,
  }
}

///|
/// Encodes any supported PDU, SMSC prefix included.
pub fn Pdu::to_octets(self : Pdu) -> Array[Byte] raise SmsError {
  match self {
    Submit(submit) => submit.to_octets()
    Deliver(deliver) => deliver.to_octets()
    StatusReport(report) => report.to_octets()
  }
}

///|
/// Encodes any supported PDU as lowercase hex.
pub fn Pdu::to_hex(self : Pdu) -> String raise SmsError {
  octets_to_hex(self.to_octets())
}

///|
/// Encodes an SMS-SUBMIT.
pub fn SmsSubmit::to_octets(self : SmsSubmit) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = []
  append_smsc(out, self.smsc)
  let has_udh = not(self.concatenation is None)
  let vpf = match self.validity {
    Default => 0
    Relative(_) => 1
    RelativeRaw(_) => 2
    Absolute(_) => 3
  }
  let first = 0x01
  | (if self.reject_duplicates { 0x04 } else { 0 })
  | (vpf << 3)
  | (if self.request_status_report { 0x20 } else { 0 })
  | (if has_udh { 0x40 } else { 0 })
  | (if self.reply_path { 0x80 } else { 0 })
  out.push(first.to_byte())
  out.push((self.message_reference & 0xFF).to_byte())
  out.append(self.destination.to_octets())
  out.push(b'\x00') // TP-PID: SME-to-SME protocol, no interworking
  out.push(dcs_of_encoding(self.encoding))
  // Absolute validity needs the timestamp before the text is packed.
  match self.validity {
    Default => ()
    Relative(minutes) => out.push(relative_validity(minutes))
    RelativeRaw(raw) => out.push(raw.to_byte())
    Absolute(stamp) => out.append(stamp.to_octets())
  }
  let header = match self.concatenation {
    Some(concat) => Some(concatenation_header(concat))
    None => None
  }
  let (ud, udl) = encode_user_data(self.encoding, self.text, self.payload, header)
  out.push(udl.to_byte())
  out.append(ud)
  out
}

///|
/// Encodes an SMS-DELIVER. Useful for building test fixtures for gateways.
pub fn SmsDeliver::to_octets(self : SmsDeliver) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = []
  append_smsc(out, self.service_center)
  let has_udh = not(self.header is None)
  let first = 0x00
  | (if self.no_more_messages { 0x04 } else { 0 })
  | (if self.status_report_indication { 0x20 } else { 0 })
  | (if has_udh { 0x40 } else { 0 })
  | (if self.reply_path { 0x80 } else { 0 })
  out.push(first.to_byte())
  out.append(self.originating.to_octets())
  out.push(b'\x00')
  out.push(dcs_of_encoding(self.encoding))
  out.append(self.timestamp.to_octets())
  let (ud, udl) = encode_user_data(self.encoding, self.text, self.payload, self.header)
  out.push(udl.to_byte())
  out.append(ud)
  out
}

///|
/// Encodes an SMS-STATUS-REPORT.
pub fn StatusReport::to_octets(self : StatusReport) -> Array[Byte] raise SmsError {
  let out : Array[Byte] = []
  append_smsc(out, self.service_center)
  let first = 0x02
  | (if self.no_more_messages { 0x04 } else { 0 })
  | (0x20)
  | (if self.reply_path { 0x80 } else { 0 })
  out.push(first.to_byte())
  out.push((self.message_reference & 0xFF).to_byte())
  out.append(self.recipient.to_octets())
  out.append(self.timestamp.to_octets())
  out.append(self.discharge_time.to_octets())
  out.push(status_code_of(self.status).to_byte())
  out.push(b'\x00')
  out
}

///|
fn status_code_of(status : StatusReportStatus) -> Int {
  match status {
    Delivered => 0
    TemporaryError(code) => code
    PermanentError(code) => code
    TemporaryUnknown(code) => code
    Other(code) => code
  }
}

///|
fn append_smsc(out : Array[Byte], smsc : Address?) -> Unit raise SmsError {
  match smsc {
    None => out.push(b'\x00')
    Some(address) => {
      let (type_, plan, digits) = match address {
        Number(type_, plan, digits) => (type_, plan, digits)
        Alphanumeric(_) => raise InvalidField("smsc cannot be alphanumeric")
      }
      let body = encode_number_digits(digits)
      let toa = (0x80 | (number_type_bits(type_) << 4) | numbering_plan_bits(plan)).to_byte()
      out.push((body.length() + 1).to_byte())
      out.push(toa)
      out.append(body)
    }
  }
}

///|
/// Builds TP-UD and TP-UDL. For GSM 7-bit the header and the text share one
/// septet stream, so the header is first expanded to septets and the text is
/// written straight after it.
fn encode_user_data(
  encoding : Encoding,
  text : StringView,
  payload : ArrayView[Byte],
  header : UserDataHeader?,
) -> (Array[Byte], Int) raise SmsError {
  match encoding {
    Gsm7 => {
      let text_septets = gsm7_to_septets(text)
      match header {
        Some(h) => {
          let header_octets = h.to_octets()
          let header_len = header_octets.length()
          // TP-UDL is octets of header plus septets of text, and the header
          // itself occupies whole octets at the front of the field.
          let header_septet_count = header_septets(header_len)
          let body_bits = 7 * text_septets.length()
          let total = header_len + (body_bits + 7) / 8
          let out = Array::make(total, b'\x00')
          write_bytes_at(out, 0, header_octets)
          write_septets(out, 0, text_septets, header_len * 8)
          (out, header_septet_count + text_septets.length())
        }
        None => (gsm7_pack(text_septets, 0), text_septets.length())
      }
    }
    EightBit => {
      let body : Array[Byte] = []
      match header {
        Some(h) => body.append(h.to_octets())
        None => ()
      }
      body.append(payload)
      let udl = body.length()
      (body, udl)
    }
    Ucs2 => {
      let body : Array[Byte] = []
      match header {
        Some(h) => body.append(h.to_octets())
        None => ()
      }
      body.append(utf8_to_ucs2(text))
      let udl = body.length()
      (body, udl)
    }
  }
}

///|
/// Maps a relative validity octet back to a duration.
fn decode_relative_validity(raw : Int) -> ValidityPeriod {
  if raw <= 143 {
    Relative((raw + 1) * 5)
  } else if raw <= 167 {
    Relative((raw - 143) * 1440)
  } else {
    Relative((raw - 166) * 10080)
  }
}

///|
/// Maps a duration to the relative validity octet.
fn relative_validity(minutes : Int) -> Byte raise SmsError {
  if minutes <= 0 {
    raise InvalidField("validity period must be positive")
  }
  if minutes <= 720 {
    return (((minutes + 4) / 5) - 1).to_byte()
  }
  if minutes % 1440 == 0 && minutes / 1440 <= 24 {
    return (144 + minutes / 1440 - 1).to_byte()
  }
  if minutes % 10080 == 0 && minutes / 10080 <= 63 {
    return (192 + minutes / 10080 - 1).to_byte()
  }
  raise InvalidField("validity period does not fit the relative format")
}

///|
fn need(octets : ArrayView[Byte], pos : Int, what : String) -> Int raise SmsError {
  guard pos < octets.length() else { raise Truncated(what) }
  octets[pos].to_int()
}
///|
pub impl Show for StatusReportStatus with fn to_string(self) {
  match self {
    Delivered => "delivered"
    TemporaryError(code) => "temporary error (\{code})"
    PermanentError(code) => "permanent error (\{code})"
    TemporaryUnknown(code) => "temporary failure (\{code})"
    Other(code) => "status \{code}"
  }
}

///|
pub impl Show for Pdu with fn to_string(self) {
  match self {
    Submit(_) => "SMS-SUBMIT"
    Deliver(_) => "SMS-DELIVER"
    StatusReport(_) => "SMS-STATUS-REPORT"
  }
}
