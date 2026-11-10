///|
/// The parts that share the user data field are the easiest to get wrong,
/// because the header and the text have to end up on the same septet stream.
test "a gsm7 message with a header keeps its text" {
  let cases : Array[@src.Concatenation] = [
    { reference: 0, total: 1, sequence: 1, },
    { reference: 255, total: 255, sequence: 255, },
    { reference: 42, total: 3, sequence: 2, },
    { reference: 70000, total: 10, sequence: 7, },
  ]
  for concat in cases {
    let submit = {
      ..@src.SmsSubmit::new(
        @src.Number(@src.International, @src.Isdn, "8613800138000"),
        "The quick brown fox",
      ),
      concatenation: Some(concat),
    }
    let back = @src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }
    match back {
      @src.Submit(got) => {
        inspect(got.text, content="The quick brown fox")
        let got_concat = got.concatenation.unwrap()
        inspect(got_concat.total, content=concat.total.to_string())
        inspect(got_concat.sequence, content=concat.sequence.to_string())
      }
      _ => fail("expected an sms-submit")
    }
  }
}

///|
test "a ucs2 message with a header keeps its text" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "中文分段测试",
      encoding=@src.Ucs2,
    ),
    concatenation: Some({ reference: 9, total: 4, sequence: 3, }),
  }
  match
    (@src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }) {
    @src.Submit(got) => {
      inspect(got.text, content="中文分段测试")
      inspect(got.concatenation.unwrap().sequence, content="3")
    }
    _ => fail("expected an sms-submit")
  }
}

///|
test "an eight bit payload with a header keeps every octet" {
  let payload : Array[Byte] = [
    b'\x00', b'\x01', b'\x7F', b'\x80', b'\xFF', b'\xAA', b'\x55',
  ]
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "",
      encoding=@src.EightBit,
    ),
    payload,
    concatenation: Some({ reference: 1, total: 2, sequence: 1, }),
  }
  match
    (@src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }) {
    @src.Submit(got) =>
      inspect(@src.octets_to_hex(got.payload), content="00017f80ffaa55")
    _ => fail("expected an sms-submit")
  }
}

///|
test "every escape character survives inside a concatenated part" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "€[]{}|^~\\",
    ),
    concatenation: Some({ reference: 5, total: 2, sequence: 1, }),
  }
  match
    (@src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }) {
    @src.Submit(got) => inspect(got.text, content="€[]{}|^~\\")
    _ => fail("expected an sms-submit")
  }
}
