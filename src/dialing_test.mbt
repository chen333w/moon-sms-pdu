///|
/// A leading `00` is an access code; a leading `0` is part of the number.
/// Getting this backwards sends the message to a different subscriber, and
/// neither the caller nor the receiver would see anything wrong.
test "the international access code is dropped, the trunk prefix is not" {
  let pdu_intl = @src.Pdu::Submit(
    @src.SmsSubmit::new(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      "x",
    ),
  ).to_hex() catch {
    e => fail(e.to_message())
  }

  // 0086... is how the number is dialled abroad, but the wire carries 86...
  let (type_, _, digits) = @src.classify_digits("008613800138000")
  inspect(type_, content="international")
  inspect(digits, content="8613800138000")

  // 0138... keeps the zero: the trunk prefix belongs to the number.
  let (type_, _, digits) = @src.classify_digits("013800138000")
  inspect(type_, content="national")
  inspect(digits, content="013800138000")

  let _ = pdu_intl
}

///|
test "a national address keeps every digit it was given" {
  let address = @src.Number(@src.National, @src.Isdn, "013800138000")
  let octets = address.to_octets() catch { e => fail(e.to_message()) }
  // Twelve digits, so the length octet says twelve and no digit is lost.
  inspect(octets[0], content="b'\\x0C'")
  let (back, _) = @src.read_address(octets, 0) catch {
    e => fail(e.to_message())
  }
  inspect(back.to_string_display(), content="013800138000")
}

///|
test "the CLI does not silently rewrite a dialled number" {
  // This is the property that matters to a caller: what they typed is what
  // goes on the wire, apart from the access code.
  let (_, _, kept) = @src.classify_digits("013800138000")
  inspect(kept.char_length(), content="12")
}
