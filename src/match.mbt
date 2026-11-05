///|
/// Comparison keys for a phone number.
///
/// The same subscriber turns up written five ways: `+86 138 0013 8000` from a
/// contact, `8613800138000` on the wire, `013800138000` from a local dialler,
/// `008613800138000` from a gateway. Matching them fails unless the comparison
/// strips the furniture first, and doing that per call site is how off-by-one
/// bugs get into address books.
pub(all) struct PhoneKey {
  /// Digits only, with the international prefix removed.
  national : String
  /// Digits only, with the country code kept as written.
  full : String
} derive(Eq, @debug.Debug)

///|
/// Builds the comparison keys for a dialled number.
///
/// Strips spaces, dashes, parentheses and the `*`/`#` dialling characters,
/// then folds the three ways of writing an international prefix into one.
pub fn phone_key(number : StringView) -> PhoneKey {
  let digits = StringBuilder()
  for ch in number {
    match ch {
      '0'..<='9' => digits.write_char(ch)
      // Dialling characters are meaningful for services, not for identity, so
      // they are kept out of the key.
      '*' | '#' => ()
      '+' => ()
      _ => ()
    }
  }
  let plain = digits.to_string()
  let full = if plain.has_prefix("00") && plain.length() > 4 {
    plain[2:].to_owned()
  } else {
    plain
  }
  // A national trunk prefix sits between the country code and the subscriber
  // number, and is not part of the identity.
  let national = if full.has_prefix("0") && full.length() > 2 {
    full[1:].to_owned()
  } else {
    full
  }
  { national, full, }
}

///|
/// True when two numbers reach the same subscriber.
///
/// The national part is only comparable when both sides carry a country code,
/// so this compares the full form and falls back to the national one. Without
/// the fallback, a local number would never match, because dropping its trunk
/// prefix leaves digits that look like a country code to the other side.
pub fn same_number(a : StringView, b : StringView) -> Bool {
  let left = phone_key(a)
  let right = phone_key(b)
  if left.full == right.full || left.national == right.national {
    return true
  }
  // A local dialled number and an international one share a subscriber suffix.
  let short = if left.national.length() < right.national.length() {
    left.national
  } else {
    right.national
  }
  let long = if left.national.length() < right.national.length() {
    right.national
  } else {
    left.national
  }
  // Require enough digits that the comparison means something.
  short.length() >= 8 && long.has_suffix(short)
}

///|
/// Compares an address against a dialled number.
pub fn Address::matches(self : Address, number : StringView) -> Bool {
  match self {
    Number(_, _, digits) => same_number(digits, number)
    // A sender that used a name has nothing to compare digits against.
    Alphanumeric(_) => false
  }
}

///|
/// Rewrites an address into its international form, so two messages from the
/// same subscriber compare equal regardless of how each was dialled.
///
/// `country_code` is needed because `013800138000` could belong to any country
/// that uses a national trunk prefix of `0`.
pub fn Address::to_international(
  self : Address,
  country_code : StringView,
) -> Address {
  match self {
    Alphanumeric(_) => self
    Number(type_, plan, digits) => {
      if type_ == International {
        return self
      }
      let key = phone_key(digits)
      Number(International, plan, country_code.to_owned() + key.national)
    }
  }
}

///|
pub impl Show for PhoneKey with fn to_string(self) {
  "\{self.full} (\{self.national})"
}
