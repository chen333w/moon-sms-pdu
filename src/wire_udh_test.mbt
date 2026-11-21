///|
/// PDUs built by a separate implementation, not by this codec.
///
/// Everything else in `udh_roundtrip_test.mbt` encodes here and decodes here,
/// which is why three defects survived it: the text start offset was wrong by
/// the header's fill bits, the escape table pointed at the wrong septets, and
/// the submit type had nowhere to keep a port header. A self-round-trip is
/// blind to all three, because both directions are wrong in the same way.
test "a concatenated part decodes to the text the sender packed" {
  let cases : Array[(String, String)] = [
    (
      "0041000D91683108108300F000001A050003000101A8E832285E4F8FD720B1FC7D7783CC6F3C",
      "The quick brown fox",
    ),
    (
      "0041000D91683108108300F000001A050003FFFFFFA8E832285E4F8FD720B1FC7D7783CC6F3C",
      "The quick brown fox",
    ),
    (
      "0041000D91683108108300F000001A0500032A0302A8E832285E4F8FD720B1FC7D7783CC6F3C",
      "The quick brown fox",
    ),
  ]
  for pair in cases {
    let (hex, text) = pair
    match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
      @src.Submit(got) => inspect(got.text, content=text)
      _ => fail("expected an sms-submit")
    }
  }
}

///|
test "a gsm7 header that is not a whole number of septets keeps the text" {
  // Six octets of concatenation header leave one fill bit, so the text starts
  // one bit into the seventh octet. Unpacking from octet zero instead returns
  // a header bit as characters and shifts everything after it.
  let hex = "0041000D91683108108300F000001A0500032A0302A8E832285E4F8FD720B1FC7D7783CC6F3C"
  match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
    @src.Submit(got) => {
      inspect(got.text, content="The quick brown fox")
      inspect(got.concatenation.unwrap().sequence, content="2")
      inspect(got.concatenation.unwrap().total, content="3")
      inspect(got.concatenation.unwrap().reference, content="42")
    }
    _ => fail("expected an sms-submit")
  }
}

///|
test "every escape position matches the standard" {
  // 3GPP TS 23.038 §6.2.1.1 defines exactly these ten. A wrong septet here is
  // silent: the text still comes out, just not the text that was sent.
  let cases : Array[(String, String)] = [
    (
      "0041000D91683108108300F000001905000305020136E50D6FE3DBA036A90D7043D9F4362F",
      "€[]{}|^~\\",
    ),
  ]
  // 0x1B followed by each escape code, packed by hand.
  for pair in cases {
    let (hex, text) = pair
    match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
      @src.Submit(got) => inspect(got.text, content=text)
      _ => fail("expected an sms-submit")
    }
  }
  inspect(@src.gsm7_septet_length("€[]{}|^~\\"), content="18")
  let septets = @src.gsm7_to_septets("€[]{}|^~\\")
  inspect(septets.length(), content="18")
  inspect(@src.gsm7_from_septets(septets), content="€[]{}|^~\\")
}

///|
test "the four punctuation escapes use the octets the standard gives them" {
  // These four are the ones an implementation gets wrong by using the ASCII
  // code point instead: { is 0x28, not 0x7B, and so on.
  let expected : Array[(String, Int32)] = [
    ("{", 40),
    ("}", 41),
    ("[", 60),
    ("]", 62),
    ("\\", 47),
    ("|", 64),
    ("^", 20),
    ("~", 61),
    ("€", 101),
  ]
  for pair in expected {
    let (ch, code) = pair
    let septets = @src.gsm7_to_septets(ch)
    inspect(septets.length(), content="2")
    inspect(septets[0].to_int(), content="27")
    inspect(septets[1].to_int(), content=code.to_string())
  }
}

///|
test "a port header survives decode and re-encode" {
  // Concatenation element plus an application port element. Keeping only the
  // concatenation half silently drops the ports, and `verify` reports it as a
  // differing octet rather than a wrong field.
  let hex = "0041000D91683108108300F00000130B00032A020105040B8423F020CB6CF61B"
  let pdu = @src.parse_pdu(hex) catch { e => fail(e.to_message()) }
  match pdu {
    @src.Submit(got) => {
      inspect(got.text, content="Hello")
      inspect(got.header.unwrap().to_octets().length(), content="12")
      inspect(
        @src.octets_to_hex(got.header.unwrap().to_octets()),
        content="0b00032a020105040b8423f0",
      )
    }
    _ => fail("expected an sms-submit")
  }
  inspect(@src.Pdu::to_hex(pdu), content=hex.to_lower())
}

///|
test "an application delivery keeps its ports through a re-encode" {
  let hex = "00400D91683108108300F00000240110010000000D0605040B8423F0C8329BFD06"
  let pdu = @src.parse_pdu(hex) catch { e => fail(e.to_message()) }
  inspect(
    @src.Pdu::to_hex(pdu),
    content="00400d91683108108300f00000240110010000000d0605040b8423f0c8329bfd06",
  )
  match pdu {
    @src.Deliver(got) => {
      inspect(got.text, content="Hello")
      inspect(Show::to_string(got.application().unwrap()), content="wap push")
    }
    _ => fail("expected an sms-deliver")
  }
}
