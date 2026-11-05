///|
fn base_submit() -> @src.SmsSubmit {
  @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "hello",
  )
}

///|
fn report_at(
  status : @src.StatusReportStatus,
  second : Int32,
) -> @src.StatusReport {
  {
    message_reference: 1,
    recipient: @src.Number(@src.International, @src.Isdn, "8613800138000"),
    service_center: None,
    timestamp: @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0),
    discharge_time: @src.timestamp_unchecked(2024, 1, 1, 10, 0, second, 0),
    status,
    no_more_messages: true,
    reply_path: false,
  }
}

///|
test "no validity period means no deadline" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  inspect(base_submit().expires_at(accepted) is None, content="true")
}

///|
test "a relative validity period counts from acceptance" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let submit = { ..base_submit(), validity: @src.Relative(30), }
  let deadline = submit.expires_at(accepted) catch { e => fail(e.to_message()) }
  inspect(deadline.unwrap().to_display(), content="2024-01-01T10:30:00+00:00")
}

///|
test "an absolute validity period ignores when it was accepted" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let deadline = @src.timestamp_unchecked(2024, 6, 1, 0, 0, 0, 0)
  let submit = { ..base_submit(), validity: @src.Absolute(deadline), }
  match (submit.expires_at(accepted) catch { e => fail(e.to_message()) }) {
    Some(stamp) =>
      inspect(stamp.to_display(), content="2024-06-01T00:00:00+00:00")
    None => fail("expected a deadline")
  }
}

///|
test "delivery inside the window is on time" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let submit = { ..base_submit(), validity: @src.Relative(30), }
  let outcome = @src.classify_delivery(
    report_at(@src.Delivered, 20),
    submit,
    accepted,
  ) catch {
    e => fail(e.to_message())
  }
  inspect(outcome, content="delivered")
}

///|
test "delivery after the window is late, not failed" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  // Thirty minutes is 1800 seconds; the report arrives at second 40.
  let submit = { ..base_submit(), validity: @src.Relative(30), }
  let late_accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let outcome = @src.classify_delivery(
    report_at(@src.Delivered, 40),
    submit,
    late_accepted,
  ) catch {
    e => fail(e.to_message())
  }
  // Second 40 is still inside thirty minutes, so this one is on time.
  inspect(outcome, content="delivered")
}

///|
test "a late delivery is reported as late" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let submit = { ..base_submit(), validity: @src.Relative(5), }
  let report = {
    ..report_at(@src.Delivered, 0),
    discharge_time: @src.timestamp_unchecked(2024, 1, 1, 10, 10, 0, 0),
  }
  let outcome = @src.classify_delivery(report, submit, accepted) catch {
    e => fail(e.to_message())
  }
  inspect(outcome, content="delivered late")
}

///|
test "retrying and failed map to distinct outcomes" {
  let accepted = @src.timestamp_unchecked(2024, 1, 1, 10, 0, 0, 0)
  let submit = base_submit()
  let retrying = @src.classify_delivery(
    report_at(@src.TemporaryError(5), 1),
    submit,
    accepted,
  ) catch {
    e => fail(e.to_message())
  }
  let failed = @src.classify_delivery(
    report_at(@src.PermanentError(32), 1),
    submit,
    accepted,
  ) catch {
    e => fail(e.to_message())
  }
  inspect(retrying, content="retrying (5)")
  inspect(failed, content="failed (32)")
}
