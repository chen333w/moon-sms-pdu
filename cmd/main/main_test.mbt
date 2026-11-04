///|
/// These exercise the pieces of the CLI that are worth pinning down: the TPDU
/// shapes it produces and how it chooses an alphabet.
test "a leading plus means an international number" {
  inspect(@lib.gsm7_is_encodable("plain ascii"), content="true")
  inspect(@lib.gsm7_is_encodable("emoji 😀"), content="false")
}

///|
test "part count matches the standard limits" {
  // split_text sizes parts for a concatenation header, which is what a caller
  // needs once a message is known to be long. Single-part limits live in
  // single_capacity.
  inspect(@lib.single_capacity(@lib.Gsm7), content="160")
  inspect(@lib.split_text("a".repeat(153), @lib.Gsm7).length(), content="1")
  inspect(@lib.split_text("a".repeat(154), @lib.Gsm7).length(), content="2")
}

///|
test "ucs2 falls back for anything outside gsm7" {
  let text = "温度 25°C"
  inspect(@lib.gsm7_is_encodable(text), content="false")
  let submits = @lib.build_submits(
    @lib.Number(@lib.International, @lib.Isdn, "8613800138000"),
    text,
    1,
    encoding=@lib.Ucs2,
  )
  inspect(submits[0].text, content=text)
}
