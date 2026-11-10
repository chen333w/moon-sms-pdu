///|
/// The buffer has to work on messages that came off the wire, not on structs
/// built in a test.
test "parts that went through the wire reassemble in the buffer" {
  let text = "The quick brown fox jumps over the lazy dog. ".repeat(5)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    11,
  ) catch {
    e => fail(e.to_message())
  }
  // Turn each submit into the deliver a handset would receive.
  let delivers : Array[@src.SmsDeliver] = []
  for submit in submits {
    let hex = @src.Pdu::Submit(submit).to_hex()
    match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
      @src.Submit(got) =>
        delivers.push({
          ..@src.SmsDeliver::new(got.destination, got.text),
          concatenation: got.concatenation,
        })
      _ => fail("expected an sms-submit")
    }
  }
  let buffer = @src.ReassemblyBuffer::new()
  let mut result = ""
  // Deliver them backwards, which is what a network under load does.
  let mut i = delivers.length() - 1
  while i >= 0 {
    match buffer.push(delivers[i], 1000UL) {
      @src.Complete(joined) => result = joined
      _ => ()
    }
    i = i - 1
  }
  inspect(result, content=text)
  inspect(buffer.pending_count(), content="0")
}

///|
test "parts from two senders do not mix" {
  let a = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "A".repeat(200),
    1,
  ) catch {
    e => fail(e.to_message())
  }
  let b = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "31624000000"),
    "B".repeat(200),
    1,
  ) catch {
    e => fail(e.to_message())
  }
  let buffer = @src.ReassemblyBuffer::new()
  let mut from_a = ""
  let mut from_b = ""
  for i, submit in a {
    let got = {
      ..@src.SmsDeliver::new(submit.destination, submit.text),
      concatenation: submit.concatenation,
    }
    match buffer.push(got, 1UL) {
      @src.Complete(joined) => from_a = joined
      _ => ()
    }
  }
  for submit in b {
    let got = {
      ..@src.SmsDeliver::new(submit.destination, submit.text),
      concatenation: submit.concatenation,
    }
    match buffer.push(got, 2UL) {
      @src.Complete(joined) => from_b = joined
      _ => ()
    }
  }
  inspect(from_a, content="A".repeat(200))
  inspect(from_b, content="B".repeat(200))
}
