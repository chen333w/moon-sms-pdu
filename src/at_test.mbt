///|
test "quoted fields keep their commas" {
  let fields = @src.split_at_fields("1,\"REC UNREAD\",\"+8613800138000\",24")
  inspect(fields.length(), content="4")
  inspect(fields[1], content="REC UNREAD")
  inspect(fields[3], content="24")
}

///|
test "the cmgs length counts the tpdu, not the smsc prefix" {
  // An SMSC prefix of 8 octets plus 18 octets of TPDU.
  let pdu = @src.hex_to_octets(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07",
  )
  inspect(@src.tpdu_length(pdu), content="30")
}

///|
test "an at+cmgs command carries the length and ends with ctrl-z" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "hi",
  )
  let command = @src.at_send(@src.Pdu::Submit(submit).to_octets())
  inspect(command.has_prefix("AT+CMGS="), content="true")
  inspect(command.has_suffix("\u{1a}"), content="true")
}

///|
test "a cmgl response with the pdu on the next line parses" {
  let response = "+CMGL: 1,0,,24\n07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\nOK\n"
  let messages = @src.parse_cmgl(response)
  inspect(messages.length(), content="1")
  inspect(messages[0].index, content="1")
  inspect(messages[0].status, content="0")
  match messages[0].pdu {
    @src.Deliver(deliver) => inspect(deliver.text, content="How are you?")
    _ => fail("expected an sms-deliver")
  }
}

///|
test "the fourth field is read as a length, not a pdu" {
  let response = "+CMGL: 2,\"REC READ\",,24\n07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07\n"
  let messages = @src.parse_cmgl(response)
  inspect(messages.length(), content="1")
  inspect(messages[0].status, content="REC READ")
  inspect(messages[0].index, content="2")
}

///|
test "a response with no messages yields an empty list" {
  let messages = @src.parse_cmgl("OK\n")
  inspect(messages.length(), content="0")
}

///|
test "the send sequence switches to pdu mode first" {
  let submit = @src.SmsSubmit::new(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    "hi",
  )
  let sequence = @src.at_send_sequence(@src.Pdu::Submit(submit).to_octets())
  inspect(sequence[0], content="AT+CMGF=0")
  inspect(sequence.length(), content="3")
}
