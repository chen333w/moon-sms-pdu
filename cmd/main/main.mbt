///|
/// `sms-pdu` decodes and builds SMS PDUs from the command line.
///
///   sms-pdu decode <hex>                  print a decoded PDU
///   sms-pdu encode <number> <text>        build an SMS-SUBMIT
///   sms-pdu parts <number> <text>         split a long message, one PDU per line
///   sms-pdu length <text>                 report how many parts and septets
fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  match args[1] {
    "decode" =>
      if args.length() < 3 {
        println("decode needs a hex string")
      } else {
        decode_cmd(args[2])
      }
    "encode" =>
      if args.length() < 4 {
        println("encode needs a number and a message")
      } else {
        encode_cmd(args[2], args[3])
      }
    "parts" =>
      if args.length() < 4 {
        println("parts needs a number and a message")
      } else {
        parts_cmd(args[2], args[3])
      }
    "length" =>
      if args.length() < 3 {
        println("length needs a message")
      } else {
        length_cmd(args[2])
      }
    "summary" =>
      if args.length() < 3 {
        println("summary needs at least one hex pdu")
      } else {
        summary_cmd(args[2:].to_owned())
      }
    "stats" =>
      if args.length() < 3 {
        println("stats needs at least one hex pdu")
      } else {
        stats_cmd(args[2:].to_owned())
      }
    "verify" =>
      if args.length() < 3 {
        println("verify needs at least one hex pdu")
      } else {
        verify_cmd(args[2:].to_owned())
      }
    "ussd" =>
      if args.length() < 3 {
        println("ussd needs a code, for example *100#")
      } else {
        ussd_cmd(args[2])
      }
    "-h" | "--help" | "help" => print_usage()
    other => println("unknown command: \{other}")
  }
}

///|
fn print_usage() -> Unit {
  println("sms-pdu — SMS PDU codec")
  println("")
  println(
    "  decode <hex>              decode an SMS-DELIVER, SUBMIT or STATUS-REPORT",
  )
  println("  encode <number> <text>    build an SMS-SUBMIT PDU")
  println("  parts <number> <text>     split a long message into PDUs")
  println("  length <text>             report part count and septet usage")
  println("  summary <hex>...          one line per PDU")
  println("  stats <hex>...            tally a batch of PDUs")
  println(
    "  verify <hex>...           re-encode each PDU and report differences",
  )
  println("  ussd <code>               encode a USSD string, for example *100#")
}

///|
fn describe_pdu(pdu : @lib.Pdu) -> Unit {
  println(pdu.to_display())
}

///|
fn decode_cmd(hex : String) -> Unit {
  match (Ok(@lib.parse_pdu(hex)) catch { e => Err(e) }) {
    Ok(pdu) => {
      describe_pdu(pdu)
      match (Ok(pdu.to_hex()) catch { e => Err(e) }) {
        Ok(reencoded) => println("re-encoded:        \{reencoded}")
        Err(e) => println("re-encode failed:  \{e.to_message()}")
      }
    }
    Err(e) => println("decode failed: \{e.to_message()}")
  }
}

///|
fn parse_number(text : String) -> @lib.Address {
  if text.has_prefix("+") {
    @lib.Number(@lib.International, @lib.Isdn, text[1:].to_owned())
  } else {
    let (type_, plan, digits) = @lib.classify_digits(text)
    @lib.Number(type_, plan, digits)
  }
}

///|
fn encode_cmd(number : String, text : String) -> Unit {
  let encoding = if @lib.gsm7_is_encodable(text) {
    @lib.Gsm7
  } else {
    @lib.Ucs2
  }
  let submit = @lib.SmsSubmit::new(parse_number(number), text, encoding~)
  match (Ok(@lib.Pdu::Submit(submit).to_hex()) catch { e => Err(e) }) {
    Ok(hex) => {
      println(hex)
      println("")
      println("encoding: \{encoding}")
      println("septets:  \{@lib.gsm7_septet_length(text)}")
    }
    Err(e) => println("encode failed: \{e.to_message()}")
  }
}

///|
fn parts_cmd(number : String, text : String) -> Unit {
  let encoding = if @lib.gsm7_is_encodable(text) {
    @lib.Gsm7
  } else {
    @lib.Ucs2
  }
  match
    (Ok(@lib.build_submits(parse_number(number), text, 42, encoding~)) catch {
      e => Err(e)
    }) {
    Ok(submits) => {
      println("// \{submits.length()} part(s), \{encoding}")
      for submit in submits {
        match (Ok(@lib.Pdu::Submit(submit).to_hex()) catch { e => Err(e) }) {
          Ok(hex) => println(hex)
          Err(e) => println("// encode failed: \{e.to_message()}")
        }
      }
    }
    Err(e) => println("failed: \{e.to_message()}")
  }
}

///|
fn length_cmd(text : String) -> Unit {
  if @lib.gsm7_is_encodable(text) {
    let septets = @lib.gsm7_septet_length(text)
    let parts = (septets + 152) / 153
    println("encoding: GSM 7-bit")
    println("septets:  \{septets}")
    println("parts:    \{if septets <= 160 { 1 } else { parts }}")
  } else {
    let units = text.char_length()
    let parts = (units * 2 + 133) / 134
    println("encoding: UCS-2")
    println("units:    \{units}")
    println("parts:    \{if units <= 70 { 1 } else { parts }}")
  }
}

///|
fn ussd_cmd(code : String) -> Unit {
  let message = @lib.UssdMessage::new(code)
  match (Ok(message.to_octets() |> @lib.octets_to_hex) catch { e => Err(e) }) {
    Ok(hex) => {
      println(hex)
      println("")
      println("encoding: \{message.encoding}")
    }
    Err(e) => println("encode failed: \{e.to_message()}")
  }
}

///|
/// Joins the remaining arguments into one capture-shaped text, so a caller can
/// paste several PDUs or one whole list.
fn collect(parts : Array[String]) -> String {
  let buf = StringBuilder()
  for part in parts {
    buf.write_string(part)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
fn summary_cmd(parts : Array[String]) -> Unit {
  let (pdus, errors) = @lib.parse_pdu_lines(collect(parts))
  for pdu in pdus {
    println(pdu.summary())
  }
  for error in errors {
    println("!: \{error}")
  }
}

///|
fn stats_cmd(parts : Array[String]) -> Unit {
  let (pdus, errors) = @lib.parse_pdu_lines(collect(parts))
  println(@lib.stats_of(pdus).to_display())
  if errors.length() > 0 {
    println("\{errors.length()} line(s) could not be parsed")
  }
}

///|
fn verify_cmd(parts : Array[String]) -> Unit {
  let problems = @lib.audit_lines(collect(parts))
  if problems.length() == 0 {
    println("all pdus round-trip identically")
  } else {
    for problem in problems {
      println(problem)
    }
  }
}
