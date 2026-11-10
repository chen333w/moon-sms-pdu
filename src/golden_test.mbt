///|
/// Fixed expected octets, taken from an independent implementation rather than
/// from this codec. A test that compares the codec with itself cannot catch a
/// field written to the wrong place, which is exactly how the default TP-PID
/// ended up as 0x40.
test "a plain submit matches octets produced elsewhere" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "Hello from MoonBit",
  )
  inspect(
    @src.Pdu::Submit(submit).to_hex(),
    content="0001000d91683108108300f0000012c8329bfd0699e5ef36a8f97ebb85693a",
  )
}

///|
test "a ucs2 submit matches octets produced elsewhere" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "你好，世界",
    encoding=@src.Ucs2,
  )
  inspect(
    @src.Pdu::Submit(submit).to_hex(),
    content="0001000d91683108108300f000080a4f60597dff0c4e16754c",
  )
}

///|
test "an ordinary submit leaves tp-pid at zero" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "hi",
  )
  // Octets 0..2 are SMSC, type and mr; 3..9 are the address; PID follows.
  let octets = @src.Pdu::Submit(submit).to_octets()
  inspect(octets[10], content="b'\\x00'")
  inspect(submit.pid, content="assigned (0)")
}

///|
test "the reference deliver decodes to its documented fields" {
  let pdu = @src.parse_pdu(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07",
  )
  match pdu {
    @src.Deliver(deliver) => {
      inspect(deliver.text, content="How are you?")
      inspect(deliver.originating.to_string_display(), content="+31641600986")
      inspect(
        deliver.service_center.unwrap().to_string_display(),
        content="+31624000000",
      )
      inspect(deliver.timestamp.year, content="2002")
      inspect(deliver.timestamp.month, content="8")
      inspect(deliver.timestamp.day, content="26")
      inspect(deliver.timestamp.hour, content="19")
      inspect(deliver.timestamp.minute, content="37")
      inspect(deliver.timestamp.second, content="41")
      inspect(deliver.encoding, content="GSM 7-bit")
    }
    _ => fail("expected an sms-deliver")
  }
}
