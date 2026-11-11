///|
test "phone_key folds the four ways of writing one number" {
  let a = phone_key("+86 138 0013 8000")
  let b = phone_key("8613800138000")
  let c = phone_key("013800138000")
  let d = phone_key("008613800138000")
  inspect(a.full, content="8613800138000")
  inspect(a.national, content="8613800138000")
  inspect(c.national, content="13800138000")
  inspect(a.full == b.full, content="true")
  inspect(a.full == d.full, content="true")
  inspect(same_number("+86 138 0013 8000", "8613800138000"), content="true")
  inspect(same_number("+86 138 0013 8000", "008613800138000"), content="true")
  // A local dialled number reaches the same subscriber.
  inspect(same_number("8613800138000", "13800138000"), content="true")
  // A different subscriber must not match.
  inspect(
    same_number("+86 138 0013 8000", "+86 138 0013 8001"),
    content="false",
  )
}
