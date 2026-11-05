///|
/// National language shift tables, 3GPP TS 23.038 §6.2.1.
///
/// The default alphabet leaves several escape positions unused. A language can
/// claim one of them, which is how Turkish gets `ğ` and `ş` into a message that
/// otherwise has to be sent as UCS-2 - eight octets instead of one per
/// character, and a third of the capacity.
///
/// Only the tables that are defined in the standard appear here. A sender and
/// receiver must agree on which table is in force; nothing in the message says
/// so, which is why these are opt-in rather than automatic.
pub(all) enum Language {
  /// No language table: escapes are the ones defined for everyone.
  Plain
  /// 3GPP TS 23.038 §6.2.1.1, single shift at 0x1B.
  Turkish
  /// Spanish, same table shape as Turkish.
  Spanish
  /// Portuguese.
  Portuguese
} derive(Eq, @debug.Debug)

///|
/// Characters a language adds, as (escape septet after 0x1B, character).
///
/// Turkish replaces six of the reserved positions. Spanish and Portuguese use
/// the same positions, which is why they need a table switch rather than being
/// folded into the default alphabet.
fn language_extension(language : Language) -> Array[(Int32, Char)] {
  match language {
    Plain => []
    Turkish =>
      [
        (0x0F, 'Ğ'),
        (0x10, 'İ'),
        (0x11, 'Ş'),
        (0x12, 'ğ'),
        (0x13, 'ı'),
        (0x14, 'ş'),
      ]
    Spanish => [(0x0F, 'ç')]
    Portuguese => [(0x0F, 'ê'), (0x10, 'ô'), (0x11, 'á'), (0x12, 'à')]
  }
}

///|
/// True when every character fits the alphabet with this language table.
pub fn gsm7_is_encodable_with(text : StringView, language : Language) -> Bool {
  let extra = language_extension(language)
  for ch in text {
    if gsm7_lookup(ch) is None {
      let mut found = false
      for pair in extra {
        if pair.1 == ch {
          found = true
        }
      }
      if !found {
        return false
      }
    }
  }
  true
}

///|
/// Encodes text using a language table for the characters the default alphabet
/// lacks.
pub fn gsm7_to_septets_with(
  text : StringView,
  language : Language,
) -> Array[Byte] raise SmsError {
  let extra = language_extension(language)
  let out : Array[Byte] = []
  for ch in text {
    match gsm7_lookup(ch) {
      Some((value, escaped)) => {
        if escaped {
          out.push(gsm7_escape.to_byte())
        }
        out.push(value.to_byte())
      }
      None => {
        let mut matched = -1
        for pair in extra {
          if pair.1 == ch {
            matched = pair.0
          }
        }
        guard matched >= 0 else { raise NotEncodable(describe_char(ch)) }
        out.push(gsm7_escape.to_byte())
        out.push(matched.to_byte())
      }
    }
  }
  out
}

///|
/// Decodes septets using a language table for the escaped positions.
pub fn gsm7_from_septets_with(
  septets : ArrayView[Byte],
  language : Language,
) -> String {
  let extra = language_extension(language)
  let buf = StringBuilder()
  let mut i = 0
  while i < septets.length() {
    let value = septets[i].to_int()
    if value == gsm7_escape {
      if i + 1 >= septets.length() {
        break
      }
      let next = septets[i + 1].to_int()
      let mut resolved = '\u{0}'
      // The language table wins over the shared extension table, because a
      // sender that switched tables expects its own characters back.
      for pair in extra {
        if pair.0 == next {
          resolved = pair.1
        }
      }
      if resolved == '\u{0}' {
        resolved = gsm7_extension_char(next)
      }
      buf.write_char(resolved)
      i = i + 2
      continue
    }
    buf.write_char(gsm7_default_char(value))
    i = i + 1
  }
  buf.to_string()
}

///|
/// Septets the text occupies under a language table, or -1 when it does not fit.
pub fn gsm7_septet_length_with(text : StringView, language : Language) -> Int32 {
  let extra = language_extension(language)
  let mut n = 0
  for ch in text {
    match gsm7_lookup(ch) {
      Some((_, escaped)) => n = n + (if escaped { 2 } else { 1 })
      None => {
        let mut found = false
        for pair in extra {
          if pair.1 == ch {
            found = true
          }
        }
        if !found {
          return -1
        }
        n = n + 2
      }
    }
  }
  n
}

///|
pub impl Show for Language with fn to_string(self) {
  match self {
    Plain => "plain"
    Turkish => "turkish"
    Spanish => "spanish"
    Portuguese => "portuguese"
  }
}
