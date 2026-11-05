///|
test "the alphabet bits decode across the general group" {
  inspect(@src.decode_dcs(0x00).encoding, content="GSM 7-bit")
  inspect(@src.decode_dcs(0x04).encoding, content="8-bit")
  inspect(@src.decode_dcs(0x08).encoding, content="UCS-2")
  inspect(@src.decode_dcs(0x10).encoding, content="GSM 7-bit")
}

///|
test "class 0 is reported as flash" {
  inspect(@src.decode_dcs(0x10).class.unwrap(), content="class 0 (flash)")
  inspect(@src.decode_dcs(0x11).class.unwrap(), content="class 1 (handset)")
  inspect(@src.decode_dcs(0x12).class.unwrap(), content="class 2 (sim)")
  inspect(@src.decode_dcs(0x13).class.unwrap(), content="class 3 (terminal)")
  inspect(@src.decode_dcs(0x00).class is None, content="true")
}

///|
test "the compression flag is surfaced, not swallowed" {
  inspect(@src.decode_dcs(0x20).compressed, content="true")
  inspect(@src.decode_dcs(0x00).compressed, content="false")
}

///|
test "message waiting groups name their kind" {
  inspect(@src.decode_dcs(0xC0).waiting.unwrap(), content="voicemail")
  inspect(@src.decode_dcs(0xC1).waiting.unwrap(), content="fax")
  inspect(@src.decode_dcs(0xC2).waiting.unwrap(), content="email")
  inspect(@src.decode_dcs(0x00).waiting is None, content="true")
}

///|
test "encoding and class survive a dcs round-trip" {
  let dcs = @src.encode_dcs(@src.Ucs2, class=@src.Flash)
  let scheme = @src.decode_dcs(dcs.to_int())
  inspect(scheme.encoding, content="UCS-2")
  inspect(scheme.class.unwrap(), content="class 0 (flash)")
  inspect(dcs, content="b'\\x18'")
}

///|
test "a flash submit keeps its class on the wire" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "flash me",
    ),
    class: Some(@src.Flash),
  }
  match @src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) {
    @src.Submit(back) => {
      inspect(back.class.unwrap(), content="class 0 (flash)")
      inspect(back.text, content="flash me")
    }
    _ => fail("expected an sms-submit")
  }
}
