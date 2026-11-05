///|
test "turkish letters would otherwise force ucs2" {
  let text = "ığşİĞŞ"
  inspect(@src.gsm7_is_encodable(text), content="false")
  inspect(@src.gsm7_is_encodable_with(text, @src.Turkish), content="true")
}

///|
test "turkish text round-trips through the language table" {
  let text = "Türkıe ığşİ"
  let septets = @src.gsm7_to_septets_with(text, @src.Turkish)
  inspect(@src.gsm7_from_septets_with(septets, @src.Turkish), content=text)
}

///|
test "a language table does not change plain ascii" {
  let text = "hello world"
  let plain = @src.gsm7_to_septets_with(text, @src.Plain)
  let turkish = @src.gsm7_to_septets_with(text, @src.Turkish)
  inspect(@src.octets_to_hex(plain), content=@src.octets_to_hex(turkish))
}

///|
test "characters outside both tables are still refused" {
  inspect(@src.gsm7_is_encodable_with("你好", @src.Turkish), content="false")
  let result = Some(@src.gsm7_to_septets_with("你", @src.Turkish)) catch {
    _ => None
  }
  inspect(result is None, content="true")
}

///|
test "the charged length counts language characters as two septets" {
  inspect(@src.gsm7_septet_length_with("ağb", @src.Turkish), content="4")
  inspect(@src.gsm7_septet_length_with("abc", @src.Turkish), content="3")
  inspect(@src.gsm7_septet_length_with("你好", @src.Turkish), content="-1")
}
