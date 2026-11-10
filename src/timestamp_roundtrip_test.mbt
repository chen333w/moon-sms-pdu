///|
/// Encoding then decoding a timestamp has to be the identity. Every existing
/// test went the other way - decode a capture, encode it back - which cannot
/// notice a field that is written to the wrong place but read back from the
/// right one.
test "a timestamp survives encode then decode" {
  let cases : Array[@src.Timestamp] = [
    @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 0),
    @src.timestamp_unchecked(2000, 1, 1, 0, 0, 0, 0),
    @src.timestamp_unchecked(2099, 12, 31, 23, 59, 59, 0),
    @src.timestamp_unchecked(2024, 2, 29, 12, 30, 45, 480),
    @src.timestamp_unchecked(2023, 7, 4, 8, 15, 30, -300),
  ]
  for stamp in cases {
    let octets = stamp.to_octets() catch { e => fail(e.to_message()) }
    let back = @src.read_timestamp(octets, 0) catch {
      e => fail(e.to_message())
    }
    inspect(back.year, content=stamp.year.to_string())
    inspect(back.month, content=stamp.month.to_string())
    inspect(back.day, content=stamp.day.to_string())
    inspect(back.hour, content=stamp.hour.to_string())
    inspect(back.minute, content=stamp.minute.to_string())
    inspect(back.second, content=stamp.second.to_string())
    inspect(back.offset_minutes(), content=stamp.offset_minutes().to_string())
  }
}

///|
test "the encoded year octet is the last two digits" {
  let stamp = @src.timestamp_unchecked(2024, 3, 1, 10, 0, 0, 0)
  let octets = stamp.to_octets() catch { e => fail(e.to_message()) }
  // 2024 is written as swapped BCD "24", which is 0x42.
  inspect(octets[0], content="b'\\x42'")
}

///|
test "a year outside the representable century is refused" {
  let old = @src.timestamp_unchecked(1999, 1, 1, 0, 0, 0, 0)
  let result = Ok(old.to_octets()) catch { e => Err(e) }
  inspect(result is Err(_), content="true")
}
