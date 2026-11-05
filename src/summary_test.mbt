///|
test "a submit summary names the destination and the part" {
  let submit = {
    ..@src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "hello",
    ),
    concatenation: Some({ reference: 1, total: 3, sequence: 2, }),
  }
  inspect(
    @src.Pdu::Submit(submit).summary(),
    content="SUBMIT -> +8613800138000 [2/3] 5 chars GSM 7-bit",
  )
}

///|
test "a deliver summary names the sender and the time" {
  let deliver = {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "31624000000"),
      "hi",
    ),
    timestamp: @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 0),
  }
  inspect(
    @src.Pdu::Deliver(deliver).summary(),
    content="DELIVER <- +31624000000 2024-03-01T10:00:00+00:00 2 chars",
  )
}

///|
test "stats count each kind separately" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "a",
  )
  let deliver = @src.SmsDeliver::new(
    @src.Number(@src.International, @src.Isdn, "31624000000"),
    "b",
  )
  let pdus : Array[@src.Pdu] = [
    @src.Submit(submit),
    @src.Deliver(deliver),
    @src.Deliver({ ..deliver, class: Some(@src.Flash), }),
    @src.Deliver({ ..deliver, encoding: @src.EightBit, }),
  ]
  let stats = @src.stats_of(pdus)
  inspect(stats.total, content="4")
  inspect(stats.submits, content="1")
  inspect(stats.delivers, content="3")
  inspect(stats.flash_messages, content="1")
  inspect(stats.binary_messages, content="1")
}

///|
test "an undelivered status report is counted as a failure" {
  let report : @src.StatusReport = {
    message_reference: 1,
    recipient: @src.Number(@src.International, @src.Isdn, "8613800138000"),
    service_center: None,
    timestamp: @src.timestamp_unchecked(2024, 1, 1, 0, 0, 0, 0),
    discharge_time: @src.timestamp_unchecked(2024, 1, 1, 0, 0, 5, 0),
    status: @src.TemporaryError(5),
    no_more_messages: true,
    reply_path: false,
  }
  let stats = @src.stats_of([@src.StatusReport(report)])
  inspect(stats.status_reports, content="1")
  inspect(stats.failed_reports, content="1")
}

///|
test "the display line omits counters that are zero" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "a",
  )
  let stats = @src.stats_of([@src.Submit(submit)])
  inspect(stats.to_display(), content="1 pdus, 1 submit")
}

///|
test "a batch parse keeps going past bad lines" {
  let text = "# capture from port 3\n\n07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\nzzzz\nOK\n"
  let (pdus, errors) = @src.parse_pdu_lines(text)
  inspect(pdus.length(), content="1")
  inspect(errors.length(), content="1")
  inspect(errors[0].has_prefix("zzzz:"), content="true")
}
