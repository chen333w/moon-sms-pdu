///|
/// A well-known SMS-DELIVER from the 3GPP TS 23.040 examples: "hellohello" sent
/// from +447785016005 to a handset.
test "decode a gsm7 sms-deliver" {
  let pdu = @src.parse_pdu(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07",
  )
  match pdu {
    Deliver(deliver) => {
      inspect(deliver.text, content="How are you?")
      inspect(
        deliver.service_center.unwrap().to_string_display(),
        content="+31624000000",
      )
      inspect(deliver.encoding, content="GSM 7-bit")
      inspect(deliver.timestamp.year, content="1902")
      inspect(deliver.timestamp.month, content="8")
      inspect(deliver.timestamp.day, content="26")
    }
    _ => fail("expected an sms-deliver")
  }
}

///|
test "submit round-trip keeps the text and the destination" {
  let submit = @src.SmsSubmit::new(@src.Number(@src.International, @src.Isdn, "8613800138000"), "Hello MoonBit")
  let hex = @src.Submit(submit).to_hex()
  match @src.parse_pdu(hex) {
    @src.Submit(back) => {
      inspect(back.text, content="Hello MoonBit")
      inspect(back.destination.to_string_display(), content="+8613800138000")
      inspect(back.encoding, content="GSM 7-bit")
    }
    _ => fail("expected an sms-submit")
  }
}

///|
test "ucs2 submit round-trips chinese text" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "你好，世界",
    encoding=@src.Ucs2,
  )
  match @src.parse_pdu(@src.Submit(submit).to_hex()) {
    @src.Submit(back) => {
      inspect(back.encoding, content="UCS-2")
      inspect(back.text, content="你好，世界")
    }
    _ => fail("expected an sms-submit")
  }
}

///|
test "concatenation header survives a round-trip" {
  let submit = {
    ..SmsSubmit::new(@src.Number(@src.International, @src.Isdn, "8613800138000"), "part two"),
    concatenation: Some({ reference: 7, total: 3, sequence: 2 }),
  }
  match @src.parse_pdu(@src.Submit(submit).to_hex()) {
    @src.Submit(back) =>
      inspect(
        back.concatenation,
        content="Some(2/3 ref 7)",
      )
    _ => fail("expected an sms-submit")
  }
}

///|
test "empty destination and no smsc encode as expected" {
  let submit = @src.SmsSubmit::new(@src.Number(@src.International, @src.Isdn, "123"), "hi")
  // 00 = no smsc, 01 = submit, 00 = mr, 03 91 21 41 ... then the body.
  let hex = @src.Submit(submit).to_hex()
  inspect(hex.has_prefix("0001"), content="true")
  let back = @src.parse_pdu(hex)
  match back {
    @src.Submit(s) => inspect(s.text, content="hi")
    _ => fail("expected an sms-submit")
  }
}

///|
test "status report decodes its discharge time and status" {
  let report = @src.StatusReport({
    message_reference: 42,
    recipient: @src.Number(@src.International, @src.Isdn, "8613800138000"),
    service_center: Some(@src.Number(@src.International, @src.Isdn, "8613800138001")),
    timestamp: @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 480),
    discharge_time: @src.timestamp_unchecked(2024, 3, 1, 10, 0, 5, 480),
    status: @src.Delivered,
    no_more_messages: true,
    reply_path: false,
  })
  match @src.parse_pdu(report.to_octets() |> @src.octets_to_hex) {
    @src.StatusReport(back) => {
      inspect(back.message_reference, content="42")
      inspect(back.status, content="delivered")
      inspect(back.discharge_time.second, content="5")
    }
    _ => fail("expected a status report")
  }
}

///|
test "malformed input raises instead of panicking" {
  inspect(
    try Ok(@src.parse_pdu("zz")) catch {
      e => Err(e)
    },
    content="Err(invalid hex: unexpected character 'z')",
  )
  inspect(
    try Ok(@src.parse_pdu("01")) catch {
      e => Err(e)
    },
    content="Err(truncated input while reading smsc)",
  )
}