///|
test "a short message stays in one part with no header" {
  let submits = @src.build_submits(
    @src.Number(@src.National, @src.Isdn, "13800138000"),
    "hi there",
    1,
  )
  inspect(submits.length(), content="1")
  inspect(submits[0].concatenation is None, content="true")
}

///|
test "a long gsm7 message splits into 153-septet parts" {
  let text = "A".repeat(400)
  let submits = @src.build_submits(
    @src.Number(@src.National, @src.Isdn, "13800138000"),
    text,
    7,
  )
  // 400 characters over three parts: 153 + 153 + 94.
  inspect(submits.length(), content="3")
  inspect(submits[0].text.char_length(), content="153")
  inspect(submits[2].text.char_length(), content="94")
  inspect(submits[1].concatenation.unwrap().sequence, content="2")
}

///|
test "each part of a long message decodes back to its own text" {
  let text = "The quick brown fox jumps over the lazy dog. ".repeat(6)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    9,
  )
  let rebuilt = StringBuilder()
  for submit in submits {
    match @src.parse_pdu(@src.Submit(submit).to_hex()) {
      @src.Submit(back) => {
        rebuilt.write_string(back.text)
        inspect(back.concatenation.unwrap().total, content="2")
      }
      _ => fail("expected an sms-submit")
    }
  }
  inspect(rebuilt.to_string().char_length(), content="270")
  inspect(rebuilt.to_string(), content=text)
}

///|
test "ucs2 parts stop on code point boundaries" {
  let text = "你好世界".repeat(40)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    3,
    encoding=@src.Ucs2,
  )
  // 160 characters is 240 octets of UTF-16, and a part holds 134 octets, so
  // this needs three parts of 67 characters each.
  inspect(submits.length(), content="3")
  inspect(submits[0].text.char_length(), content="67")
  let rebuilt = StringBuilder()
  for submit in submits {
    match @src.parse_pdu(@src.Submit(submit).to_hex()) {
      @src.Submit(back) => rebuilt.write_string(back.text)
      _ => fail("expected an sms-submit")
    }
  }
  inspect(rebuilt.to_string(), content=text)
}

///|
test "assembly waits for every part and ignores duplicates" {
  let make = fn(sequence : Int32) -> @src.SmsDeliver {
    {
      originating: @src.Number(@src.International, @src.Isdn, "8613800138000"),
      service_center: None,
      timestamp: @src.timestamp_unchecked(2024, 1, 1, 0, 0, 0, 0),
      encoding: @src.Gsm7,
      class: None,
      compressed: false,
      waiting: None,
      text: "part\{sequence}",
      payload: [],
      header: None,
      concatenation: Some({ reference: 1, total: 3, sequence, }),
      no_more_messages: true,
      status_report_indication: false,
      reply_path: false,
    }
  }
  inspect(@src.assemble([make(2), make(1)]) is None, content="true")
  inspect(
    @src.assemble([make(2), make(1), make(3), make(2)]).unwrap(),
    content="part1part2part3",
  )
}

///|
test "a concatenated part survives encode and decode byte for byte" {
  let text = "The quick brown fox jumps over the lazy dog. ".repeat(8)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    42,
  )
  let collected : Array[@src.SmsDeliver] = []
  for submit in submits {
    let hex = @src.Pdu::Submit(submit).to_hex()
    match @src.parse_pdu(hex) {
      @src.Submit(back) => {
        // Re-encoding must produce the same octets, or interop is broken.
        inspect(@src.Pdu::Submit(back).to_hex(), content=hex)
        inspect(back.text, content=submit.text)
      }
      _ => fail("expected an sms-submit")
    }
  }
  let _ = collected
}
