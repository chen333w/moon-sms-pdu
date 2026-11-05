///|
test "a delete command round-trips" {
  let command = @src.SmsCommand::delete(
    @src.Number(@src.International, @src.Isdn, "8613800138000"),
    17,
  )
  let hex = @src.Pdu::Command(command).to_hex()
  match @src.parse_pdu(hex) {
    @src.Command(back) => {
      inspect(back.command_type, content="delete message")
      inspect(back.target_message_reference, content="17")
      inspect(back.destination.to_string_display(), content="+8613800138000")
      inspect(@src.Pdu::Command(back).to_hex(), content=hex)
    }
    _ => fail("expected an sms-command")
  }
}

///|
test "every command type survives encode and decode" {
  let kinds : Array[@src.CommandType] = [
    @src.ReadMessage,
    @src.DeleteMessage,
    @src.MessageDeposit,
    @src.SubmitMessage,
    @src.StatusEnquiry,
  ]
  for kind in kinds {
    let command = {
      ..@src.SmsCommand::delete(
        @src.Number(@src.National, @src.Isdn, "13800138000"),
        1,
      ),
      command_type: kind,
    }
    let hex = @src.Pdu::Command(command).to_hex()
    match @src.parse_pdu(hex) {
      @src.Command(back) => {
        inspect(back.command_type, content=kind.to_string())
        inspect(@src.Pdu::Command(back).to_hex(), content=hex)
      }
      _ => fail("expected an sms-command")
    }
  }
}

///|
test "an unknown command code is kept rather than rejected" {
  let command = {
    ..@src.SmsCommand::delete(
      @src.Number(@src.National, @src.Isdn, "13800138000"),
      1,
    ),
    command_type: @src.Other(6),
  }
  let hex = @src.Pdu::Command(command).to_hex()
  match @src.parse_pdu(hex) {
    @src.Command(back) => inspect(back.command_type, content="command (6)")
    _ => fail("expected an sms-command")
  }
}

///|
test "tp-pid decodes each of its four ranges" {
  inspect(@src.decode_pid(0x40), content="short message")
  inspect(@src.decode_pid(0x00), content="assigned (0)")
  inspect(@src.decode_pid(0x41), content="replace short message")
  inspect(@src.decode_pid(0x90), content="voice telephony")
  inspect(@src.decode_pid(0xC2), content="sc specific (2)")
}

///|
test "a telematic pid marks the message as interworking" {
  inspect(@src.decode_pid(0x90).is_interworking(), content="true")
  inspect(@src.decode_pid(0x00).is_interworking(), content="false")
  let pid = @src.decode_pid(0x92)
  inspect(pid, content="voice telephony to sme-b")
}

///|
test "pid round-trips through every range" {
  let pids : Array[@src.ProtocolId] = [
    @src.Assigned(5),
    @src.MessageType(@src.ReplaceShortMessage),
    @src.MessageType(@src.SimDataDownload),
    @src.Telematic(@src.TelefaxGroup3, Some(@src.SmeA)),
    @src.ScSpecific(9),
  ]
  for pid in pids {
    let octet = @src.encode_pid(pid)
    inspect(@src.decode_pid(octet.to_int()), content=pid.to_string())
  }
}

///|
test "a delivery keeps the pid the network sent" {
  let deliver = {
    ..@src.SmsDeliver::new(
      @src.Number(@src.International, @src.Isdn, "31624000000"),
      "sim download",
    ),
    pid: @src.MessageType(@src.SimDataDownload),
  }
  match @src.parse_pdu(@src.Pdu::Deliver(deliver).to_hex()) {
    @src.Deliver(back) => {
      inspect(back.pid, content="sim data download")
      inspect(back.text, content="sim download")
    }
    _ => fail("expected an sms-deliver")
  }
}
