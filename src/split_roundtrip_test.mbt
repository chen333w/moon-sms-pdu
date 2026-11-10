///|
/// Text split into parts and reassembled through the wire has to come back
/// byte for byte. This is the path an actual modem takes.
test "a long gsm7 message survives split, encode, decode and reassemble" {
  let texts : Array[String] = [
    "a".repeat(153),
    "a".repeat(154),
    "a".repeat(400),
    "The quick brown fox jumps over the lazy dog. ".repeat(10),
  ]
  for text in texts {
    let submits = @src.build_submits(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      text,
      42,
    ) catch {
      e => fail(e.to_message())
    }
    let rebuilt = StringBuilder()
    for submit in submits {
      let hex = @src.Pdu::Submit(submit).to_hex()
      match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
        @src.Submit(got) => rebuilt.write_string(got.text)
        _ => fail("expected an sms-submit")
      }
    }
    inspect(rebuilt.to_string(), content=text)
  }
}

///|
test "a long ucs2 message survives split, encode, decode and reassemble" {
  let texts : Array[String] = [
    "中".repeat(67),
    "中".repeat(68),
    "中文测试内容".repeat(30),
  ]
  for text in texts {
    let submits = @src.build_submits(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      text,
      7,
      encoding=@src.Ucs2,
    ) catch {
      e => fail(e.to_message())
    }
    let rebuilt = StringBuilder()
    for submit in submits {
      let hex = @src.Pdu::Submit(submit).to_hex()
      match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
        @src.Submit(got) => rebuilt.write_string(got.text)
        _ => fail("expected an sms-submit")
      }
    }
    inspect(rebuilt.to_string(), content=text)
  }
}

///|
test "splitting never cuts an escaped character in half" {
  // Every euro is two septets, so a naive byte split would strand a 0x1B.
  let text = "€".repeat(200)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    3,
  ) catch {
    e => fail(e.to_message())
  }
  for submit in submits {
    // Each part must hold a whole number of two-septet characters.
    inspect(submit.text.char_length() * 2 <= 153, content="true")
  }
}
