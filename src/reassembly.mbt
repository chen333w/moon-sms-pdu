///|
/// Collects the parts of a multi-part message as they arrive.
///
/// `assemble` needs every part up front, which is fine for a batch but wrong
/// for a modem: parts arrive one at a time, out of order, sometimes twice, and
/// a sender that gives up leaves a partial message behind. This buffer keeps
/// the pending messages and lets the caller clear the ones that went stale.
pub(all) struct ReassemblyBuffer {
  /// Pending messages, keyed by sender and concatenation reference.
  pending : Map[String, PendingMessage]
  /// Seconds a part can sit before `expire` will drop it.
  timeout_seconds : Int32
}

///|
/// One message being reassembled.
pub(all) struct PendingMessage {
  reference : Int32
  total : Int32
  /// Parts received so far, keyed by sequence number.
  parts : Map[Int32, String]
  /// When the first part of this message was seen, in seconds since the epoch.
  started_at : UInt64
  originating : String
} derive(Eq, @debug.Debug)

///|
/// What `ReassemblyBuffer::push` produced.
pub(all) enum PushResult {
  /// The part was filed; more are still missing.
  Pending(Int32, Int32)
  /// This part completed the message.
  Complete(String)
  /// The part had already been seen and was dropped.
  Duplicate
  /// The part is not part of a concatenated message at all.
  Single(String)
  /// The part contradicts what is already buffered, so it was refused.
  Rejected(String)
} derive(Eq, @debug.Debug)

///|
/// Builds an empty buffer.
pub fn ReassemblyBuffer::new(timeout_seconds? : Int32) -> ReassemblyBuffer {
  { pending: Map([]), timeout_seconds: timeout_seconds.unwrap_or(600), }
}

///|
/// Key a sender and reference together. A reference is only unique per sender,
/// so two people sending at once must not collide.
fn reassembly_key(originating : String, reference : Int32) -> String {
  "\{originating}#\{reference}"
}

///|
/// Files one part and reports what happened.
pub fn ReassemblyBuffer::push(
  self : ReassemblyBuffer,
  deliver : SmsDeliver,
  now : UInt64,
) -> PushResult {
  let concatenation = match deliver.concatenation {
    Some(c) => c
    None => return Single(deliver.text)
  }
  let sender = deliver.originating.to_string_display()
  let key = reassembly_key(sender, concatenation.reference)
  let existing = self.pending.get(key)
  let message = match existing {
    Some(message) =>
      if message.total != concatenation.total {
        // Same reference, different part count: the sender reused the number
        // before the old message finished. Dropping the stale one is safer
        // than mixing parts from two messages.
        return Rejected("part count changed for this reference")
      } else {
        message
      }
    None => {
      let fresh = {
        reference: concatenation.reference,
        total: concatenation.total,
        parts: Map([]),
        started_at: now,
        originating: sender,
      }
      self.pending.set(key, fresh)
      fresh
    }
  }
  if message.parts.contains(concatenation.sequence) {
    return Duplicate
  }
  message.parts.set(concatenation.sequence, deliver.text)
  if message.parts.length() < message.total {
    return Pending(message.parts.length(), message.total)
  }
  let ordered : Array[String] = []
  for i = 1; i <= message.total; i = i + 1 {
    match message.parts.get(i) {
      Some(text) => ordered.push(text)
      None => return Pending(message.parts.length(), message.total)
    }
  }
  self.pending.remove(key)
  Complete(ordered.join(""))
}

///|
/// Drops every partial message older than the timeout and returns how many were
/// removed. Call this on a timer; a buffer that is never expired leaks the
/// parts of messages whose sender gave up.
pub fn ReassemblyBuffer::expire(self : ReassemblyBuffer, now : UInt64) -> Int32 {
  let limit = self.timeout_seconds.reinterpret_as_uint().to_uint64()
  let stale : Array[String] = []
  for key, message in self.pending {
    let age = if now >= message.started_at {
      now - message.started_at
    } else {
      0UL
    }
    if age > limit {
      stale.push(key)
    }
  }
  for key in stale {
    self.pending.remove(key)
  }
  stale.length()
}

///|
/// Number of messages still missing parts.
pub fn ReassemblyBuffer::pending_count(self : ReassemblyBuffer) -> Int32 {
  self.pending.length()
}

///|
pub impl Show for PushResult with fn to_string(self) {
  match self {
    Pending(received, total) => "Pending(\{received}, \{total})"
    Complete(text) => "Complete(\{text})"
    Duplicate => "Duplicate"
    Single(text) => "Single(\{text})"
    Rejected(reason) => "Rejected(\{reason})"
  }
}
