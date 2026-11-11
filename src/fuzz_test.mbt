///|
/// Truncated input must raise, never read past the end. A modem supplies a
/// half-written line more often than anyone expects, and a decoder that
/// silently reads garbage turns a bad capture into wrong data.
test "every truncation of a real pdu is refused, not misread" {
  let full = @src.hex_to_octets(
    "07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07",
  )
  for cut = 1; cut < full.length(); cut = cut + 1 {
    let prefix = full[:cut]
    let result = Ok(@src.parse_octets(prefix)) catch { e => Err(e) }
    // Either it refuses, or it decodes to the same message. Anything else
    // means a field was read from bytes that belong to the next one.
    match result {
      Ok(parsed) =>
        match parsed {
          @src.Deliver(deliver) =>
            if deliver.text != "How are you?" {
              fail("truncating at \{cut} produced '\{deliver.text}'")
            }
          _ => ()
        }
      Err(_) => ()
    }
  }
}

///|
test "a declared length longer than the buffer is refused" {
  // Claim 255 septets of user data in a PDU that carries twelve.
  let octets = @src.hex_to_octets(
    "07911326040000F0040B911346610089F6000020806291731408FFC8F71D14969741F977FD07",
  )
  let result = Ok(@src.parse_octets(octets)) catch { e => Err(e) }
  inspect(result is Err(_), content="true")
}

///|
test "a corrupted header length does not overrun" {
  let octets = @src.hex_to_octets("0041000d91683108108300f04000FF00032a0301a8")
  let result = Ok(@src.parse_octets(octets)) catch { e => Err(e) }
  inspect(result is Err(_), content="true")
}

///|
test "random octets never panic" {
  // A fixed sequence, so a failure is reproducible.
  let cases : Array[String] = [
    "00", "0000", "000000", "FF", "FFFFFFFF", "0011", "0004ff", "07911326040000F004",
    "0001000000", "0041000d91683108108300f0", "0001000d91683108108300f0000808", "00ff00ff00ff",
  ]
  for hex in cases {
    let octets = @src.hex_to_octets(hex)
    let _ = Ok(@src.parse_octets(octets)) catch { _ => Err(()) }
  }
}
