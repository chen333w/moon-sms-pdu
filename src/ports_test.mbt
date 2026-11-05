///|
test "wap push is recognised by its destination port" {
  inspect(
    @src.classify_ports({ destination: 2948, source: 9200, }),
    content="wap push",
  )
}

///|
test "mms is told apart from wap push by its source port" {
  inspect(
    @src.classify_ports({ destination: 2948, source: 9202, }),
    content="mms notification",
  )
  inspect(
    @src.classify_ports({ destination: 2948, source: 9200, }),
    content="wap push",
  )
}

///|
test "device management and provisioning are separate ports" {
  inspect(
    @src.classify_ports({ destination: 4996, source: 9200, }),
    content="device management",
  )
  inspect(
    @src.classify_ports({ destination: 4995, source: 9200, }),
    content="client provisioning",
  )
}

///|
test "an unknown port keeps both numbers" {
  inspect(
    @src.classify_ports({ destination: 12345, source: 54321, }),
    content="port 12345 from 54321",
  )
}

///|
test "an application delivery survives a round-trip with its payload" {
  let deliver = @src.SmsDeliver::to_application(
    @src.Number(@src.International, @src.Isdn, "31624000000"),
    { destination: 2948, source: 9200, },
    [b'\x01', b'\x06', b'\x03', b'\xBE', b'\x1A', b'\x00'],
  ) catch {
    e => fail(e.to_message())
  }
  let hex = @src.Pdu::Deliver(deliver).to_hex()
  match @src.parse_pdu(hex) {
    @src.Deliver(back) => {
      inspect(back.application().unwrap(), content="wap push")
      inspect(@src.octets_to_hex(back.payload), content="010603be1a00")
      inspect(@src.Pdu::Deliver(back).to_hex(), content=hex)
    }
    _ => fail("expected an sms-deliver")
  }
}

///|
test "a plain message has no application" {
  let deliver = @src.SmsDeliver::new(
    @src.Number(@src.International, @src.Isdn, "31624000000"),
    "hello",
  )
  inspect(deliver.application() is None, content="true")
}
