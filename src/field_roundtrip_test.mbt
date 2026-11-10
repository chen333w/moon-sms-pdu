///|
/// Every field written has to be read back unchanged. Grouped in one place so
/// a new field is hard to add without a case here.
test "every submit field survives encode then decode" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "hello",
    ),
    message_reference: 200,
    class: Some(@src.Flash),
    pid: @src.Assigned(7),
    request_status_report: true,
    reply_path: true,
    reject_duplicates: true,
    validity: @src.Relative(120),
  }
  let back = @src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
    e => fail(e.to_message())
  }
  match back {
    @src.Submit(got) => {
      inspect(got.message_reference, content="200")
      inspect(got.class.unwrap(), content="class 0 (flash)")
      inspect(got.pid, content="assigned (7)")
      inspect(got.request_status_report, content="true")
      inspect(got.reply_path, content="true")
      inspect(got.reject_duplicates, content="true")
      inspect(got.text, content="hello")
    }
    _ => fail("expected an sms-submit")
  }
}

///|
test "an absolute validity period survives encode then decode" {
  let deadline = @src.timestamp_unchecked(2024, 6, 1, 12, 0, 0, 480)
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "hi",
    ),
    validity: @src.Absolute(deadline),
  }
  match
    (@src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }) {
    @src.Submit(got) =>
      match got.validity {
        @src.Absolute(stamp) => {
          inspect(stamp.year, content="2024")
          inspect(stamp.month, content="6")
          inspect(stamp.hour, content="12")
          inspect(stamp.offset_minutes(), content="480")
        }
        _ => fail("expected an absolute validity period")
      }
    _ => fail("expected an sms-submit")
  }
}

///|
test "the three relative validity ranges survive encode then decode" {
  // Minutes, days and weeks are encoded in different parts of one octet.
  // One value from each of the four ranges, plus the top of the last two.
  let cases : Array[Int32] = [30, 240, 720, 1440, 41760, 10080, 594720]
  for minutes in cases {
    let submit = {
      ..@src.SmsSubmit::new(
        @src.Number(@src.International, @src.Isdn, "8613800138000"),
        "hi",
      ),
      validity: @src.Relative(minutes),
    }
    let back = @src.parse_pdu(@src.Pdu::Submit(submit).to_hex()) catch {
      e => fail(e.to_message())
    }
    match back {
      @src.Submit(got) =>
        match got.validity {
          @src.Relative(got_minutes) =>
            inspect(got_minutes, content=minutes.to_string())
          _ => fail("expected a relative validity period")
        }
      _ => fail("expected an sms-submit")
    }
  }
}
