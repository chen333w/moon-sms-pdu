///|
test "a ussd balance reply round-trips" {
  let ussd = @src.UssdMessage::new("*100#")
  let octets = ussd.to_octets()
  let back = @src.UssdMessage::parse(octets) catch { e => fail(e.to_message()) }
  inspect(back.text, content="*100#")
  inspect(back.encoding, content="GSM 7-bit")
}

///|
test "a ussd reply with chinese text uses ucs2" {
  let ussd = @src.UssdMessage::new("余额 12.50 元")
  inspect(ussd.encoding, content="UCS-2")
  let back = @src.UssdMessage::parse(ussd.to_octets()) catch {
    e => fail(e.to_message())
  }
  inspect(back.text, content="余额 12.50 元")
}

///|
test "a ussd body without a leading dcs still decodes" {
  let body = @src.gsm7_pack(@src.gsm7_to_septets("*100#"), 0)
  let ussd = @src.UssdMessage::parse(body, has_dcs=false) catch {
    e => fail(e.to_message())
  }
  inspect(ussd.text, content="*100#")
}
