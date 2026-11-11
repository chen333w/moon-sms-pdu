///|
/// One line describing a PDU, for logs and list views.
///
/// The full decoded struct is better when you have it in hand. This exists for
/// the case where a trace file holds thousands of PDUs and you want to scan
/// them without printing five lines each.
pub fn Pdu::summary(self : Pdu) -> String {
  match self {
    Submit(submit) => {
      let head = "SUBMIT -> \{submit.destination.to_string_display()}"
      let body = "\{submit.text.char_length()} chars \{submit.encoding}"
      match submit.concatenation {
        Some(c) => "\{head} [\{c.sequence}/\{c.total}] \{body}"
        None => "\{head} \{body}"
      }
    }
    Deliver(deliver) => {
      let head = "DELIVER <- \{deliver.originating.to_string_display()}"
      let body = "\{deliver.timestamp.to_display()} \{deliver.text.char_length()} chars"
      match deliver.concatenation {
        Some(c) => "\{head} [\{c.sequence}/\{c.total}] \{body}"
        None => "\{head} \{body}"
      }
    }
    StatusReport(report) =>
      "STATUS mr=\{report.message_reference} \{report.status} at \{report.discharge_time.to_display()}"
    Command(command) =>
      "COMMAND \{command.command_type} mr=\{command.target_message_reference}"
  }
}

///|
/// Counters over a batch of PDUs.
pub(all) struct PduStats {
  mut total : Int32
  mut submits : Int32
  mut delivers : Int32
  mut status_reports : Int32
  mut commands : Int32
  /// Deliveries the SMSC still had queued behind them.
  mut more_messages_pending : Int32
  /// Flash messages, which handsets do not store.
  mut flash_messages : Int32
  /// Eight-bit payloads, whose text field is not meaningful.
  mut binary_messages : Int32
  /// Parts of multi-part messages.
  mut concatenated_parts : Int32
  /// Status reports that did not say "delivered".
  mut failed_reports : Int32
} derive(Eq, @debug.Debug)

///|
/// Builds an empty tally.
pub fn PduStats::new() -> PduStats {
  {
    total: 0,
    submits: 0,
    delivers: 0,
    status_reports: 0,
    commands: 0,
    more_messages_pending: 0,
    flash_messages: 0,
    binary_messages: 0,
    concatenated_parts: 0,
    failed_reports: 0,
  }
}

///|
/// Folds one PDU into the tally.
pub fn PduStats::add(self : PduStats, pdu : Pdu) -> Unit {
  self.total = self.total + 1
  match pdu {
    Submit(submit) => {
      self.submits = self.submits + 1
      if submit.class is Some(Flash) {
        self.flash_messages = self.flash_messages + 1
      }
      if submit.encoding == EightBit {
        self.binary_messages = self.binary_messages + 1
      }
      if submit.concatenation is Some(_) {
        self.concatenated_parts = self.concatenated_parts + 1
      }
    }
    Deliver(deliver) => {
      self.delivers = self.delivers + 1
      if !deliver.no_more_messages {
        self.more_messages_pending = self.more_messages_pending + 1
      }
      if deliver.class is Some(Flash) {
        self.flash_messages = self.flash_messages + 1
      }
      if deliver.encoding == EightBit {
        self.binary_messages = self.binary_messages + 1
      }
      if deliver.concatenation is Some(_) {
        self.concatenated_parts = self.concatenated_parts + 1
      }
    }
    StatusReport(report) => {
      self.status_reports = self.status_reports + 1
      if !(report.status is Delivered) {
        self.failed_reports = self.failed_reports + 1
      }
    }
    Command(_) => self.commands = self.commands + 1
  }
}

///|
/// Renders the tally, skipping counters that are zero so a short log stays
/// short.
pub fn PduStats::to_display(self : PduStats) -> String {
  let parts : Array[String] = ["\{self.total} pdus"]
  if self.submits > 0 {
    parts.push("\{self.submits} submit")
  }
  if self.delivers > 0 {
    parts.push("\{self.delivers} deliver")
  }
  if self.status_reports > 0 {
    parts.push("\{self.status_reports} status")
  }
  if self.commands > 0 {
    parts.push("\{self.commands} command")
  }
  if self.concatenated_parts > 0 {
    parts.push("\{self.concatenated_parts} part")
  }
  if self.flash_messages > 0 {
    parts.push("\{self.flash_messages} flash")
  }
  if self.binary_messages > 0 {
    parts.push("\{self.binary_messages} binary")
  }
  if self.failed_reports > 0 {
    parts.push("\{self.failed_reports} undelivered")
  }
  if self.more_messages_pending > 0 {
    parts.push("\{self.more_messages_pending} queued")
  }
  parts.join(", ")
}

///|
/// Reads a list of PDUs, one per line, reporting the ones that failed rather
/// than stopping at the first bad line.
///
/// A capture file usually has a header, a blank line or a stray `OK` in it.
/// Throwing the whole batch away over one of those is worse than skipping it.
pub fn parse_pdu_lines(text : StringView) -> (Array[Pdu], Array[String]) {
  let pdus : Array[Pdu] = []
  let errors : Array[String] = []
  for raw in text.split("\n") {
    let line = raw.to_owned().trim()
    if line.is_empty() || line.has_prefix("#") || line.has_prefix("//") {
      continue
    }
    // Modem chatter that a capture will contain and that is not a PDU.
    if is_at_chatter(line) {
      continue
    }
    let result = Ok(parse_pdu(line)) catch { e => Err(e) }
    match result {
      Ok(pdu) => pdus.push(pdu)
      Err(e) => errors.push("\{line}: \{e.to_message()}")
    }
  }
  (pdus, errors)
}

///|
fn is_at_chatter(line : StringView) -> Bool {
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
/// Tallies a batch in one call.
pub fn stats_of(pdus : ArrayView[Pdu]) -> PduStats {
  let stats = PduStats::new()
  for pdu in pdus {
    stats.add(pdu)
  }
  stats
}

///|
pub impl Show for PduStats with fn to_string(self) {
  self.to_display()
}

///|
/// Renders a PDU as labelled lines, the shape a person reads when they are
/// staring at one message rather than scanning many.
///
/// Field names follow the standard's abbreviations, because anyone debugging a
/// modem will have the spec open next to the terminal.
pub fn Pdu::to_display(self : Pdu) -> String {
  let lines : Array[String] = []
  match self {
    Submit(submit) => {
      lines.push("SMS-SUBMIT")
      lines.push("  TP-MR       \{submit.message_reference}")
      lines.push("  TP-DA       \{submit.destination.to_string_display()}")
      lines.push("  TP-PID      \{submit.pid}")
      lines.push("  TP-DCS      \{submit.encoding}")
      match submit.class {
        Some(c) => lines.push("  TP-DCS cl.  \{c}")
        None => ()
      }
      lines.push("  TP-VP       \{describe_validity(submit.validity)}")
      lines.push("  TP-UDL      \{submit.text.char_length()} chars")
      match submit.concatenation {
        Some(c) =>
          lines.push(
            "  UDH concat  \{c.sequence}/\{c.total} ref \{c.reference}",
          )
        None => ()
      }
      lines.push("  TP-UD       \{submit.text}")
    }
    Deliver(deliver) => {
      lines.push("SMS-DELIVER")
      match deliver.service_center {
        Some(smsc) => lines.push("  SMSC        \{smsc.to_string_display()}")
        None => lines.push("  SMSC        (from the modem)")
      }
      lines.push("  TP-OA       \{deliver.originating.to_string_display()}")
      lines.push("  TP-SCTS     \{deliver.timestamp.to_display()}")
      lines.push("  TP-PID      \{deliver.pid}")
      lines.push("  TP-DCS      \{deliver.encoding}")
      match deliver.class {
        Some(c) => lines.push("  TP-DCS cl.  \{c}")
        None => ()
      }
      match deliver.waiting {
        Some(w) => lines.push("  TP-DCS mwi  \{w}")
        None => ()
      }
      if deliver.compressed {
        lines.push("  TP-DCS cmp  compressed")
      }
      match deliver.application() {
        Some(app) => lines.push("  App port    \{app}")
        None => ()
      }
      match deliver.concatenation {
        Some(c) =>
          lines.push(
            "  UDH concat  \{c.sequence}/\{c.total} ref \{c.reference}",
          )
        None => ()
      }
      if deliver.encoding == EightBit {
        lines.push("  TP-UD       \{octets_to_hex(deliver.payload)} (binary)")
      } else {
        lines.push("  TP-UD       \{deliver.text}")
      }
    }
    StatusReport(report) => {
      lines.push("SMS-STATUS-REPORT")
      lines.push("  TP-MR       \{report.message_reference}")
      lines.push("  TP-RA       \{report.recipient.to_string_display()}")
      lines.push("  TP-SCTS     \{report.timestamp.to_display()}")
      lines.push("  TP-DT       \{report.discharge_time.to_display()}")
      lines.push("  TP-ST       \{report.status}")
    }
    Command(command) => {
      lines.push("SMS-COMMAND")
      lines.push("  TP-MR       \{command.message_reference}")
      lines.push("  TP-DA       \{command.destination.to_string_display()}")
      lines.push("  TP-CT       \{command.command_type}")
      lines.push("  TP-MN       \{command.target_message_reference}")
    }
  }
  lines.join("\n")
}

///|
fn describe_validity(validity : ValidityPeriod) -> String {
  match validity {
    Default => "SMSC default"
    Relative(minutes) => "\{minutes} minutes"
    RelativeRaw(raw) => "raw octet \{raw}"
    Absolute(stamp) => stamp.to_display()
  }
}
