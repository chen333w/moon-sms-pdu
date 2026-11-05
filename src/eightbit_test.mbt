///|
test "an alphanumeric originator decodes from a deliver pdu" {
  // "MyBank" packed as an alphanumeric TP-OA, then "OK" as GSM 7-bit.
  let deliver = {
    ..@src.SmsDeliver::new((@src.Alphanumeric("MyBank") : @src.Address), "OK"),
    timestamp: @src.timestamp_unchecked(2024, 5, 6, 12, 30, 0, 480),
  }
  let hex = @src.Pdu::Deliver(deliver).to_hex()
  match @src.parse_pdu(hex) {
    @src.Deliver(back) => {
      inspect(back.originating.to_string_display(), content="MyBank")
      inspect(back.text, content="OK")
      inspect(@src.Pdu::Deliver(back).to_hex(), content=hex)
    }
    _ => fail("expected an sms-deliver")
  }
}

///|
test "an eight bit payload survives untouched" {
  let deliver = {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "31624000000"),
      "",
      encoding=@src.EightBit,
    ),
    service_center: Some(
      @src.Number(@src.International, @src.Isdn, "31624000001"),
    ),
    timestamp: @src.timestamp_unchecked(2024, 5, 6, 12, 30, 0, 0),
    payload: [b'\x00', b'\xFF', b'\x10', b'\x7F'],
  }
  let hex = @src.Pdu::Deliver(deliver).to_hex()
  match @src.parse_pdu(hex) {
    @src.Deliver(back) => {
      inspect(back.encoding, content="8-bit")
      inspect(@src.octets_to_hex(back.payload), content="00ff107f")
      inspect(@src.Pdu::Deliver(back).to_hex(), content=hex)
    }
    _ => fail("expected an sms-deliver")
  }
}

///|
test "port addressing is readable from a header" {
  let header = @src.UserDataHeader::new([
    @src.HeaderElement::new(@src.iei_application_port_16bit, [
      b'\x0B', b'\x84', b'\x23', b'\xF0',
    ]),
  ])
  match header.ports() {
    Some(ports) => {
      inspect(ports.destination, content="2948")
      inspect(ports.source, content="9200")
    }
    None => fail("expected ports")
  }
}
