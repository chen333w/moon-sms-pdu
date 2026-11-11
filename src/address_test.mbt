///|
test "a plus prefix decodes to an international number" {
  let address = @src.Number(@src.International, @src.Isdn, "31624000000")
  let octets = address.to_octets()
  // 0x91 is "international, ISDN"; the digits are swapped nibbles.
  inspect(octets[1], content="b'\\x91'")
  let (back, next) = @src.read_address(octets, 0)
  inspect(back.to_string_display(), content="+31624000000")
  inspect(next, content="8")
}

///|
test "an odd number of digits pads the last semi-octet with f" {
  let address = @src.Number(@src.International, @src.Isdn, "1234567")
  let octets = address.to_octets()
  inspect(octets[0], content="b'\\x07'")
  inspect(octets[5], content="b'\\xF7'")
  let (back, _) = @src.read_address(octets, 0)
  inspect(back.to_string_display(), content="+1234567")
}

///|
test "an alphanumeric originator round-trips" {
  let address = (@src.Alphanumeric("MyBank") : @src.Address)
  let octets = address.to_octets()
  let (back, _) = @src.read_address(octets, 0)
  inspect(back.to_string_display(), content="MyBank")
}

///|
test "digit classification follows the trunk and access prefixes" {
  let (type_, plan, digits) = @src.classify_digits("008613800138000")
  inspect(type_, content="international")
  inspect(plan, content="isdn")
  inspect(digits, content="8613800138000")
  // The national trunk prefix stays: it is part of the number, and removing
  // it would deliver to a different subscriber.
  let (type_, plan, digits) = @src.classify_digits("013800138000")
  inspect(type_, content="national")
  inspect(plan, content="isdn")
  inspect(digits, content="013800138000")
  let (type_, plan, digits) = @src.classify_digits("13800138000")
  inspect(type_, content="national")
  inspect(plan, content="isdn")
  inspect(digits, content="13800138000")
}

///|
test "dialling characters survive the round-trip" {
  let address = @src.Number(@src.Unknown, @src.Isdn, "*123#")
  let octets = address.to_octets()
  let (back, _) = @src.read_address(octets, 0)
  inspect(back.to_string_display(), content="*123#")
}

///|
test "an address longer than twenty digits is refused" {
  let too_long = @src.Number(
    @src.International,
    @src.Isdn,
    "123456789012345678901",
  )
  let result = Ok(too_long.to_octets()) catch { e => Err(e) }
  inspect(result is Err(_), content="true")
}

///|
test "twenty digits is the boundary and still encodes" {
  let longest = @src.Number(
    @src.International,
    @src.Isdn,
    "12345678901234567890",
  )
  let octets = longest.to_octets() catch { e => fail(e.to_message()) }
  inspect(octets[0], content="b'\\x14'")
}
