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
  println("  ussd <code>               encode a USSD string, for example *100#")
}

///|
fn describe_pdu(pdu : @lib.Pdu) -> Unit {
  match pdu {
    @lib.Submit(submit) => {
      println("type:              SMS-SUBMIT")
      println("destination:       \{submit.destination.to_string_display()}")
      println("encoding:          \{submit.encoding}")
      match submit.class {
        Some(c) => println("class:             \{c}")
        None => ()
      }
      println("text:              \{submit.text}")
      println("status report:     \{submit.request_status_report}")
      match submit.concatenation {
        Some(c) =>
          println(
            "concatenation:     \{c.sequence} of \{c.total}, ref \{c.reference}",
          )
        None => ()
      }
    }
    @lib.Deliver(deliver) => {
      println("type:              SMS-DELIVER")
      println("originator:        \{deliver.originating.to_string_display()}")
      match deliver.service_center {
        Some(smsc) => println("service center:    \{smsc.to_string_display()}")
        None => println("service center:    (from the modem)")
      }
      println("time:              \{deliver.timestamp}")
      println("encoding:          \{deliver.encoding}")
      match deliver.class {
        Some(c) => println("class:             \{c}")
        None => ()
      }
      match deliver.waiting {
        Some(w) => println("message waiting:   \{w}")
        None => ()
      }
      if deliver.compressed {
        println("compressed:        yes (payload left as-is)")
      }
      println("text:              \{deliver.text}")
      match deliver.concatenation {
        Some(c) =>
          println(
            "concatenation:     \{c.sequence} of \{c.total}, ref \{c.reference}",
          )
        None => ()
      }
      match deliver.header {
        Some(header) =>
          match header.ports() {
            Some(ports) =>
              println(
                "ports:             \{ports.destination} -> \{ports.source}",
              )
            None => ()
          }
        None => ()
      }
    }
    @lib.StatusReport(report) => {
      println("type:              SMS-STATUS-REPORT")
      println("message ref:       \{report.message_reference}")
      println("recipient:         \{report.recipient.to_string_display()}")
      println("sent:              \{report.timestamp}")
      println("discharged:        \{report.discharge_time}")
      println("status:            \{report.status}")
    }
  }
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
