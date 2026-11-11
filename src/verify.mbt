///|
/// What a round-trip check found.
pub(all) enum RoundTripResult {
  /// Decoding and re-encoding produced the same octets.
  Identical
  /// The octets differ, with the explanation of where.
  Mismatch(Int32, Byte, Byte)
  /// The PDU could not be decoded at all.
  Undecodable(String)
} derive(Eq, @debug.Debug)

///|
/// Decodes a PDU and encodes it again, then compares the two.
///
/// A gateway accepts a message only if its own re-encoding matches, so this is
/// the check worth running against a capture before trusting the codec with
/// production traffic. Reporting the first differing octet is more useful than
/// a bare boolean: it points straight at the field that was read wrong.
pub fn round_trip(pdu : ArrayView[Byte]) -> RoundTripResult {
  let decoded = Ok(parse_octets(pdu)) catch { e => Err(e) }
  match decoded {
    Err(e) => Undecodable(e.to_message())
    Ok(parsed) => {
      let reencoded = Ok(parsed.to_octets()) catch { e => Err(e) }
      match reencoded {
        Err(e) => Undecodable(e.to_message())
        Ok(out) => compare_octets(pdu, out)
      }
    }
  }
}

///|
fn compare_octets(
  left : ArrayView[Byte],
  right : ArrayView[Byte],
) -> RoundTripResult {
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i = 0; i < shared; i = i + 1 {
    if left[i] != right[i] {
      return Mismatch(i, left[i], right[i])
    }
  }
  if left.length() != right.length() {
    // Length alone differs; report the first octet past the shorter end.
    let index = shared
    let original = if index < left.length() { left[index] } else { b'\x00' }
    let produced = if index < right.length() { right[index] } else { b'\x00' }
    return Mismatch(index, original, produced)
  }
  Identical
}

///|
/// What an audit pass found, including how much it looked at.
///
/// The count matters: an empty capture and a clean capture both produce no
/// problems, and reporting "all good" for a file with nothing in it is worse
/// than saying nothing.
pub(all) struct AuditReport {
  checked : Int32
  problems : Array[String]
}

///|
/// Runs `round_trip` over a batch.
pub fn audit(text : StringView) -> AuditReport {
  let problems = audit_lines(text)
  let checked = parse_pdu_lines(text).0.length()
  { checked, problems, }
}

///|
/// Runs `round_trip` over a batch and returns only the ones that are not
/// identical, paired with their original hex.
pub fn audit_lines(text : StringView) -> Array[String] {
  let report : Array[String] = []
  for raw in text.split("\n") {
    let line = raw.to_owned().trim()
    if line.is_empty() || line.has_prefix("#") || line.has_prefix("//") {
      continue
    }
    if is_chatter(line) {
      continue
    }
    let octets = Ok(hex_to_octets(line)) catch { e => Err(e) }
    match octets {
      // A line that is not hex at all is still worth reporting: it means the
      // capture has something in it that is not a PDU.
      Err(e) => report.push("\{line}: \{e.to_message()}")
      Ok(bytes) =>
        match round_trip(bytes) {
          Identical => ()
          Mismatch(index, original, produced) =>
            report.push(
              "\{line}: octet \{index} was \{octets_to_hex([original][:])}, came back \{octets_to_hex([produced][:])}",
            )
          Undecodable(reason) => report.push("\{line}: \{reason}")
        }
    }
  }
  report
}

///|
fn is_chatter(line : StringView) -> Bool {
  if line == "OK" || line == "ERROR" {
    true
  } else {
    line.has_prefix("+CMGS:") ||
    line.has_prefix("+CMGL:") ||
    line.has_prefix("AT+") ||
    line.has_prefix("+CUSD:") ||
    line.has_prefix("+CMTI:")
  }
}

///|
pub impl Show for RoundTripResult with fn to_string(self) {
  match self {
    Identical => "identical"
    Mismatch(index, original, produced) =>
      "octet \{index}: was \{original}, came back \{produced}"
    Undecodable(reason) => "undecodable: \{reason}"
  }
}
