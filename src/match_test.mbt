///|
test "the same number written five ways compares equal" {
  inspect(@src.same_number("+8613800138000", "8613800138000"), content="true")
  inspect(@src.same_number("+8613800138000", "013800138000"), content="true")
  inspect(@src.same_number("+8613800138000", "008613800138000"), content="true")
  inspect(
    @src.same_number("+86 138 0013 8000", "8613800138000"),
    content="true",
  )
  inspect(
    @src.same_number("(86) 138-0013-8000", "+8613800138000"),
    content="true",
  )
}

///|
test "different numbers do not compare equal" {
  inspect(@src.same_number("+8613800138000", "+8613800138001"), content="false")
  inspect(@src.same_number("13800138000", "31624000000"), content="false")
}

///|
test "the key strips dialling characters" {
  let key = @src.phone_key("*100#")
  inspect(key.full, content="100")
}

///|
test "an address matches a dialled number" {
  let address = @src.Number(@src.International, @src.Isdn, "8613800138000")
  inspect(address.matches("+86 138 0013 8000"), content="true")
  inspect(address.matches("13800138001"), content="false")
}

///|
test "an alphabetic sender cannot be matched by number" {
  let address : @src.Address = @src.Alphanumeric("MyBank")
  inspect(address.matches("8613800138000"), content="false")
}

///|
test "rewriting to international makes two spellings equal" {
  let local = @src.Number(@src.National, @src.Isdn, "013800138000")
  let rewritten = local.to_international("86")
  inspect(rewritten.to_string_display(), content="+8613800138000")
}
