///|
/// Characters outside the basic plane occupy two UTF-16 code units, so they
/// cost four octets of UCS-2 and must never be split down the middle.
test "an emoji survives a ucs2 round-trip" {
  let emoji = "😀"
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    emoji,
    encoding=@src.Ucs2,
  )
  let hex = @src.Pdu::Submit(submit).to_hex() catch {
    e => fail(e.to_message())
  }
  // U+1F600 is D83D DE00 in UTF-16BE, and TP-UDL counts octets.
  inspect(hex, content="0001000d91683108108300f0000804d83dde00")
  match (@src.parse_pdu(hex) catch { e => fail(e.to_message()) }) {
    @src.Submit(got) => inspect(got.text, content=emoji)
    _ => fail("expected an sms-submit")
  }
}

///|
test "splitting counts a surrogate pair as four octets" {
  // Each emoji is four octets, so a 134 octet part holds 33 of them, rounding
  // down to stay on a code point boundary.
  let many = "😀".repeat(80)
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    many,
    1,
    encoding=@src.Ucs2,
  ) catch {
    e => fail(e.to_message())
  }
  inspect(submits.length(), content="3")
  inspect(submits[0].text.char_length(), content="33")
  let rebuilt = StringBuilder()
  for submit in submits {
    rebuilt.write_string(submit.text)
  }
  inspect(rebuilt.to_string(), content=many)
}

///|
test "an emoji cannot be squeezed into gsm 7-bit" {
  inspect(@src.gsm7_is_encodable("😀"), content="false")
  inspect(@src.gsm7_septet_length("😀"), content="-1")
  inspect(@src.fits_single("😀", @src.Gsm7), content="false")
  inspect(@src.fits_single("😀", @src.Ucs2), content="true")
}
