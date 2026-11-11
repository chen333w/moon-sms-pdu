///|
test "gsm7 default alphabet round-trip covers every assigned code" {
  let text = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  let septets = gsm7_to_septets(text)
  inspect(septets.length(), content="62")
  inspect(gsm7_from_septets(septets), content=text)
}

///|
test "gsm7 extension characters cost two septets" {
  inspect(gsm7_septet_length("a€b"), content="4")
  inspect(gsm7_septet_length("abc"), content="3")
  let septets = gsm7_to_septets("€")
  inspect(septets.length(), content="2")
  inspect(gsm7_from_septets(septets), content="€")
}

///|
test "gsm7 rejects characters outside the alphabet" {
  inspect(gsm7_is_encodable("hello €"), content="true")
  inspect(gsm7_is_encodable("你好"), content="false")
  inspect(gsm7_septet_length("你好"), content="-1")
}

///|
test "gsm7 packing matches the worked example from the spec" {
  // "hellohello" is the classic 10-septet sample: 9 octets when packed.
  let septets = gsm7_to_septets("hellohello")
  let octets = gsm7_pack(septets, 0)
  inspect(octets.length(), content="9")
  let back = gsm7_unpack(octets, septets.length(), 0)
  inspect(gsm7_from_septets(back), content="hellohello")
}

///|
test "gsm7 packing with a header offset shifts the stream" {
  let septets = gsm7_to_septets("hellohello")
  let octets = gsm7_pack(septets, 6)
  // 6 bits of header + 70 bits of payload = 76 bits, which needs 10 octets.
  inspect(octets.length(), content="10")
  let back = gsm7_unpack(octets, septets.length(), 6)
  inspect(gsm7_from_septets(back), content="hellohello")
}

///|
test "gsm7 fit_septets follows the truncation rule" {
  // 160 septets fit exactly in 140 octets with no header.
  inspect(gsm7_fit_septets(140, 0), content="160")
  // The second argument is fill bits, not octets. A six octet header ends six
  // bits into a septet, leaving 1114 bits and room for 159 septets, of which
  // the header's own seven septets leave 152 for text.
  inspect(gsm7_fit_septets(140, 6), content="159")
  inspect(gsm7_fit_septets(140, 6) - 7, content="152")
  // A header that ends exactly on a septet boundary pads by one bit instead.
  inspect(header_fill_bits(6), content="1")
  inspect(gsm7_fit_septets(140, 6) - 6, content="153")
}

///|
test "gsm7 decoding tolerates a dangling escape" {
  let septets = [b'\x41', b'\x1b']
  inspect(gsm7_from_septets(septets), content="A")
}
