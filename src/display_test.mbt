///|
test "a deliver renders with field labels" {
  let deliver = {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "31624000000"),
      "hello",
    ),
    timestamp: @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 0),
  }
  let text = @src.Pdu::Deliver(deliver).to_display()
  inspect(text.contains_char('\n'), content="true")
  inspect(text.contains("SMS-DELIVER"), content="true")
  inspect(text.contains("+31624000000"), content="true")
  inspect(text.contains("2024-03-01T10:00:00+00:00"), content="true")
  inspect(text.contains("hello"), content="true")
}

///|
test "a binary delivery shows hex rather than mojibake" {
  let deliver = {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "31624000000"),
      "",
      encoding=@src.EightBit,
    ),
    payload: [b'\x01', b'\x02', b'\xFF'],
  }
  let text = @src.Pdu::Deliver(deliver).to_display()
  inspect(text.contains("0102ff"), content="true")
  inspect(text.contains("binary"), content="true")
}

///|
test "a submit lists its validity period" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "hi",
    ),
    validity: @src.Relative(30),
  }
  let text = @src.Pdu::Submit(submit).to_display()
  inspect(text.contains("30 minutes"), content="true")
  inspect(text.contains("TP-VP"), content="true")
}

///|
test "the display names the application port" {
  let deliver = @src.SmsDeliver::to_application(
    @src.Number(@src.International, @src.Isdn, "31624000000"),
    { destination: 2948, source: 9200, },
    [b'\x01'],
  ) catch {
    e => fail(e.to_message())
  }
  inspect(
    @src.Pdu::Deliver(deliver).to_display().contains("wap push"),
    content="true",
  )
}
