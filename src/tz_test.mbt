///|
/// The time zone is stored in quarter hours with the sign in bit 3, so the
/// octet is not a plain number and a wrong reading shifts every timestamp.
test "every quarter hour offset survives encode then decode" {
  let offsets : Array[Int32] = [
    0, 15, 30, 45, 60, 330, 480, 525, 840, -60, -300, -480, -720,
  ]
  for offset in offsets {
    let stamp = @src.timestamp_unchecked(2024, 6, 15, 12, 30, 0, offset)
    let octets = stamp.to_octets() catch { e => fail(e.to_message()) }
    let back = @src.read_timestamp(octets, 0) catch {
      e => fail(e.to_message())
    }
    inspect(back.offset_minutes(), content=offset.to_string())
  }
}

///|
test "negative zero keeps its sign bit" {
  // 0x08 is zero offset with the negative flag set. It means UTC, but a codec
  // that normalises it writes 0x00 and breaks a byte comparison.
  let raw = @src.hex_to_octets("42301021030008")
  let stamp = @src.read_timestamp(raw, 0) catch { e => fail(e.to_message()) }
  inspect(stamp.offset_minutes(), content="0")
  let back = stamp.to_octets() catch { e => fail(e.to_message()) }
  inspect(back[6], content="b'\\x08'")
}

///|
test "a real pdu with a positive offset decodes to the right instant" {
  // Same message as the reference capture but with +08:00 in the SCTS.
  let stamp = @src.read_timestamp(@src.hex_to_octets("42605121030023"), 0) catch {
    e => fail(e.to_message())
  }
  inspect(stamp.year, content="2024")
  inspect(stamp.offset_minutes(), content="480")
  // 12:30 at +08:00 is 04:30 UTC.
  inspect(stamp.to_unix(), content="1718425800")
}
