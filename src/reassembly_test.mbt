///|
fn part_message(
  sequence : Int32,
  total : Int32,
  text : String,
) -> @src.SmsDeliver {
  {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      text,
    ),
    concatenation: Some({ reference: 5, total, sequence, }),
  }
}

///|
test "parts arriving out of order still complete" {
  let buffer = @src.ReassemblyBuffer::new()
  inspect(buffer.push(part_message(2, 3, "B"), 100UL), content="Pending(1, 3)")
  inspect(buffer.push(part_message(1, 3, "A"), 101UL), content="Pending(2, 3)")
  inspect(buffer.push(part_message(3, 3, "C"), 102UL), content="Complete(ABC)")
  inspect(buffer.pending_count(), content="0")
}

///|
test "a repeated part is dropped instead of appended twice" {
  let buffer = @src.ReassemblyBuffer::new()
  let _ = buffer.push(part_message(1, 2, "A"), 100UL)
  inspect(buffer.push(part_message(1, 2, "A"), 101UL), content="Duplicate")
  inspect(buffer.push(part_message(2, 2, "B"), 102UL), content="Complete(AB)")
}

///|
test "a whole message is passed straight through" {
  let buffer = @src.ReassemblyBuffer::new()
  let single = @src.SmsDeliver::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "hello",
  )
  inspect(buffer.push(single, 100UL), content="Single(hello)")
}

///|
test "stale partials are expired and counted" {
  let buffer = @src.ReassemblyBuffer::new(timeout_seconds=60)
  let _ = buffer.push(part_message(1, 3, "A"), 100UL)
  inspect(buffer.pending_count(), content="1")
  inspect(buffer.expire(200UL), content="1")
  inspect(buffer.pending_count(), content="0")
}

///|
test "two senders can use the same reference without colliding" {
  let buffer = @src.ReassemblyBuffer::new()
  let from_a = part_message(1, 2, "A")
  let from_b = {
    ..part_message(1, 2, "X"),
    originating: @src.Number(@src.International, @src.Isdn, "31624000000"),
  }
  let _ = buffer.push(from_a, 100UL)
  let _ = buffer.push(from_b, 100UL)
  inspect(buffer.pending_count(), content="2")
}

///|
test "a changed part count is refused rather than mixed" {
  let buffer = @src.ReassemblyBuffer::new()
  let _ = buffer.push(part_message(1, 3, "A"), 100UL)
  inspect(
    buffer.push(part_message(2, 4, "B"), 101UL),
    content="Rejected(part count changed for this reference)",
  )
}
