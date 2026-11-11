///|
test "a real pdu round-trips identically" {
  let octets = @src.hex_to_octets(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07",
  )
  inspect(@src.round_trip(octets), content="identical")
}

///|
test "a mangled pdu reports where it diverged" {
  // Flip the time zone octet: it re-encodes, but not to the same byte.
  let octets = @src.hex_to_octets(
    "07911326040000F0040B911346610089F6000020806291731408F0C8F71D14969741F977FD07",
  )
  let result = @src.round_trip(octets)
  inspect(result is @src.Identical, content="false")
}

///|
test "truncated input is reported as undecodable" {
  let octets = @src.hex_to_octets("0791")
  match @src.round_trip(octets) {
    @src.Undecodable(_) => ()
    _ => fail("expected an undecodable result")
  }
}

///|
test "an audit of a good capture is empty" {
  let text = "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\n"
  inspect(@src.audit_lines(text).length(), content="0")
}

///|
test "an audit names the line that failed" {
  let text = "OK\nzzzz\n07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\n"
  let problems = @src.audit_lines(text)
  inspect(problems.length(), content="1")
  inspect(problems[0].has_prefix("zzzz:"), content="true")
}

///|
/// An empty capture and a clean capture both have no problems. The report has
/// to tell them apart, or a mistyped filename reads as a passing audit.
test "an audit reports how much it checked" {
  let empty = @src.audit("")
  inspect(empty.checked, content="0")
  inspect(empty.problems.length(), content="0")

  let one = @src.audit(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\n",
  )
  inspect(one.checked, content="1")
  inspect(one.problems.length(), content="0")
}

///|
test "an audit counts the good lines even when one is bad" {
  let report = @src.audit(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\nzzzz\n",
  )
  inspect(report.checked, content="1")
  inspect(report.problems.length(), content="1")
}
