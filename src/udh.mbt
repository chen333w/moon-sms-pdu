///|
/// One Information Element of a user data header.
pub(all) struct HeaderElement {
  id : Int
  data : Array[Byte]
} derive(Eq, @debug.Debug)

///|
/// A user data header: its elements, in wire order.
pub(all) struct UserDataHeader {
  elements : Array[HeaderElement]
} derive(Eq, @debug.Debug)

///|
/// Concatenation element with an 8-bit reference.
pub let iei_concatenated_8bit : Int = 0x00

///|
/// Concatenation element with a 16-bit reference.
pub let iei_concatenated_16bit : Int = 0x08

///|
/// Application port addressing, 8-bit ports.
pub let iei_application_port_8bit : Int = 0x04

///|
/// Application port addressing, 16-bit ports.
pub let iei_application_port_16bit : Int = 0x05

///|
/// Where a part sits in a multi-part message.
pub(all) struct Concatenation {
  reference : Int
  total : Int
  sequence : Int
} derive(Eq, @debug.Debug)

///|
/// Application port pair, as used by OTA provisioning and WAP push.
pub(all) struct Ports {
  destination : Int
  source : Int
} derive(Eq, @debug.Debug)

///|
/// Parses a header from the start of TP-UD. Returns the header and how many
/// octets it occupies, including its own length octet.
pub fn UserDataHeader::parse(
  octets : ArrayView[Byte],
) -> (UserDataHeader, Int) raise SmsError {
  guard octets.length() >= 1 else { raise Truncated("user data header") }
  let length = octets[0].to_int()
  guard length >= 1 else { raise InvalidField("empty user data header") }
  guard 1 + length <= octets.length() else {
    raise BadLength("user data header claims \{length} octets")
  }
  let elements : Array[HeaderElement] = []
  let mut pos = 1
  while pos < 1 + length {
    guard pos + 1 < 1 + length else {
      raise BadLength("truncated information element")
    }
    let id = octets[pos].to_int()
    let data_len = octets[pos + 1].to_int()
    guard pos + 2 + data_len <= 1 + length else {
      raise BadLength("information element overruns the header")
    }
    elements.push({ id, data: octets[pos + 2:pos + 2 + data_len].to_owned() })
    pos = pos + 2 + data_len
  }
  ({ elements, }, length + 1)
}

///|
/// Serialises the header, writing the length octet from its contents.
pub fn UserDataHeader::to_octets(self : UserDataHeader) -> Array[Byte] {
  let body : Array[Byte] = []
  for element in self.elements {
    body.push(element.id.to_byte())
    body.push(element.data.length().to_byte())
    body.append(element.data)
  }
  let out : Array[Byte] = [ body.length().to_byte() ]
  out.append(body)
  out
}

///|
/// Reads the concatenation element, if the header carries one.
pub fn UserDataHeader::concatenation(self : UserDataHeader) -> Concatenation? {
  for element in self.elements {
    if element.id == iei_concatenated_8bit && element.data.length() == 3 {
      return Some({
        reference: element.data[0].to_int(),
        total: element.data[1].to_int(),
        sequence: element.data[2].to_int(),
      })
    }
    if element.id == iei_concatenated_16bit && element.data.length() == 4 {
      return Some({
        reference: (element.data[0].to_int() << 8) | element.data[1].to_int(),
        total: element.data[2].to_int(),
        sequence: element.data[3].to_int(),
      })
    }
  }
  None
}

///|
/// Reads the application port element, if the header carries one.
pub fn UserDataHeader::ports(self : UserDataHeader) -> Ports? {
  for element in self.elements {
    if element.id == iei_application_port_8bit && element.data.length() == 2 {
      return Some({
        destination: element.data[0].to_int(),
        source: element.data[1].to_int(),
      })
    }
    if element.id == iei_application_port_16bit && element.data.length() == 4 {
      return Some({
        destination: (element.data[0].to_int() << 8) | element.data[1].to_int(),
        source: (element.data[2].to_int() << 8) | element.data[3].to_int(),
      })
    }
  }
  None
}

///|
/// Builds a header holding a single concatenation element. References that fit
/// in one octet use the 8-bit element, larger ones the 16-bit element.
pub fn concatenation_header(
  concatenation : Concatenation,
) -> UserDataHeader raise SmsError {
  guard concatenation.total >= 1 && concatenation.total <= 255 else {
    raise InvalidField("concatenation total out of range")
  }
  guard concatenation.sequence >= 1 && concatenation.sequence <= concatenation.total else {
    raise InvalidField("concatenation sequence out of range")
  }
  if concatenation.reference >= 0 && concatenation.reference <= 0xFF {
    {
      elements: [
        {
          id: iei_concatenated_8bit,
          data: [
            concatenation.reference.to_byte(), concatenation.total.to_byte(),
            concatenation.sequence.to_byte(),
          ],
        },
      ],
    }
  } else {
    {
      elements: [
        {
          id: iei_concatenated_16bit,
          data: [
            ((concatenation.reference >> 8) & 0xFF).to_byte(),
            (concatenation.reference & 0xFF).to_byte(),
            concatenation.total.to_byte(), concatenation.sequence.to_byte(),
          ],
        },
      ],
    }
  }
}
///|
pub impl Show for Concatenation with fn to_string(self) {
  "\{self.sequence}/\{self.total} ref \{self.reference}"
}

///|
pub impl Show for UserDataHeader with fn to_string(self) {
  let ids : Array[String] = []
  for element in self.elements {
    ids.push("0x" + element.id.to_string(radix=16))
  }
  "header[" + ids.join(",") + "]"
}
