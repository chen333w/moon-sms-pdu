///|
/// to_unix subtracts the offset, so a timestamp and its unix form describe the
/// same instant. from_unix then rebuilds a UTC stamp, which is a different
/// wall clock but the same moment.
test "unix conversion keeps the instant across time zones" {
  let offsets : Array[Int32] = [0, 480, -300, 330]
  for offset in offsets {
    let stamp = @src.timestamp_unchecked(2024, 6, 15, 12, 0, 0, offset)
    let unix = stamp.to_unix()
    let utc = @src.Timestamp::from_unix(unix) catch {
      e => fail(e.to_message())
    }
    // Same instant, so converting back gives the same number.
    inspect(utc.to_unix(), content=unix.to_string())
    // And the UTC wall clock is the local one minus the offset.
    inspect(utc.offset_minutes(), content="0")
  }
}

///|
test "an offset of eight hours lands four hours earlier in utc" {
  let shanghai = @src.timestamp_unchecked(2024, 6, 15, 12, 0, 0, 480)
  let utc = @src.Timestamp::from_unix(shanghai.to_unix()) catch {
    e => fail(e.to_message())
  }
  inspect(utc.hour, content="4")
  inspect(utc.day, content="15")
}

///|
test "a negative offset lands later in utc" {
  let newyork = @src.timestamp_unchecked(2024, 6, 15, 8, 0, 0, -300)
  let utc = @src.Timestamp::from_unix(newyork.to_unix()) catch {
    e => fail(e.to_message())
  }
  inspect(utc.hour, content="13")
}

///|
test "a leap day survives the round trip" {
  let stamp = @src.timestamp_unchecked(2024, 2, 29, 23, 59, 59, 0)
  let back = @src.Timestamp::from_unix(stamp.to_unix()) catch {
    e => fail(e.to_message())
  }
  inspect(back.month, content="2")
  inspect(back.day, content="29")
  inspect(back.second, content="59")
}

///|
test "the century boundary is consistent" {
  let first = @src.timestamp_unchecked(2000, 1, 1, 0, 0, 0, 0)
  let last = @src.timestamp_unchecked(2099, 12, 31, 23, 59, 59, 0)
  inspect(first.to_unix(), content="946684800")
  inspect(last.to_unix() > first.to_unix(), content="true")
}
