///|
/// Errors surfaced by the PDU codec.
pub suberror SmsError {
  /// The input ended before the field being read was complete.
  Truncated(String)
  /// A hex string had an odd length or a non-hex character.
  InvalidHex(String)
  /// A field carried a value the spec does not define, or this codec rejects.
  InvalidField(String)
  /// The text cannot be represented in the requested data coding scheme.
  NotEncodable(String)
  /// A user data field did not match its declared length.
  BadLength(String)
} derive(@debug.Debug)

///|
pub impl Show for SmsError with fn to_string(self) {
  self.to_message()
}

///|
/// Renders an error as a short human readable line.
pub fn SmsError::to_message(self : SmsError) -> String {
  match self {
    Truncated(what) => "truncated input while reading \{what}"
    InvalidHex(what) => "invalid hex: \{what}"
    InvalidField(what) => "invalid field: \{what}"
    NotEncodable(what) => "not encodable: \{what}"
    BadLength(what) => "bad length: \{what}"
  }
}
