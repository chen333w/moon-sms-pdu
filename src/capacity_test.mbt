///|
/// Capacity limits and alphabet selection, as the CLI relies on them.
test "a leading plus means an international number" {
  inspect(@src.gsm7_is_encodable("plain ascii"), content="true")
  inspect(@src.gsm7_is_encodable("emoji 😀"), content="false")
}

///|
test "part count matches the standard limits" {
  // split_text sizes parts for a concatenation header, which is what a caller
  // needs once a message is known to be long. Single-part limits live in
  // single_capacity.
  inspect(@src.single_capacity(@src.Gsm7), content="160")
  inspect(@src.split_text("a".repeat(153), @src.Gsm7).length(), content="1")
  inspect(@src.split_text("a".repeat(154), @src.Gsm7).length(), content="2")
}

///|
test "ucs2 falls back for anything outside gsm7" {
  let text = "温度 25°C"
  inspect(@src.gsm7_is_encodable(text), content="false")
  let submits = @src.build_submits(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    text,
    1,
    encoding=@src.Ucs2,
  )
  inspect(submits[0].text, content=text)
}
