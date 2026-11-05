///|
test "a known instant maps to the right unix second" {
  // 2024-03-01T10:00:00Z is 1709287200.
  let stamp = @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 0)
  inspect(stamp.to_unix(), content="1709287200")
  let back = @src.Timestamp::from_unix(1709287200L) catch {
    e => fail(e.to_message())
  }
  inspect(back.year, content="2024")
  inspect(back.month, content="3")
  inspect(back.day, content="1")
  inspect(back.hour, content="10")
}

///|
test "the time zone offset is subtracted to reach utc" {
  // Same wall clock, but +08:00 means 02:00 UTC.
  let stamp = @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 480)
  inspect(stamp.to_unix(), content="1709258400")
}

///|
test "unix conversion round-trips across a leap day" {
  let stamp = @src.timestamp_unchecked(2024, 2, 29, 23, 59, 59, 0)
  let back = @src.Timestamp::from_unix(stamp.to_unix()) catch {
    e => fail(e.to_message())
  }
  inspect(back.to_display(), content=stamp.to_display())
}

///|
test "adding seconds crosses a day boundary" {
  let stamp = @src.timestamp_unchecked(2024, 3, 1, 23, 0, 0, 0)
  let later = stamp.add_seconds(7200L) catch { e => fail(e.to_message()) }
  inspect(later.day, content="2")
  inspect(later.hour, content="1")
}

///|
test "comparison orders timestamps" {
  let early = @src.timestamp_unchecked(2024, 1, 1, 0, 0, 0, 0)
  let late = @src.timestamp_unchecked(2024, 1, 1, 0, 0, 1, 0)
  inspect(early.is_before(late), content="true")
  inspect(late.is_before(early), content="false")
  inspect(late.seconds_since(early), content="1")
}

///|
test "rfc3339 writes the offset out" {
  let stamp = @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 480)
  inspect(stamp.to_rfc3339(), content="2024-03-01T10:00:00+08:00")
}
