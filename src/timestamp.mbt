///|
/// A TP-SCTS / TP-VP-absolute timestamp: six swapped-BCD fields followed by a
/// time zone expressed in quarter hours.
///
/// The time zone is kept as the raw octet it arrived in. That looks pedantic
/// until you meet a real SMSC: the sign lives in bit 3, so `0x08` means
/// "zero offset, negative", which a plain integer offset would silently rewrite
/// to `0x00`. Keeping the octet makes re-encoding byte for byte identical.
pub(all) struct Timestamp {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  tz_raw : Int
} derive(Eq, @debug.Debug)

///|
/// Builds a timestamp from calendar fields and an offset in minutes. The offset
/// must be a whole number of quarter hours.
pub fn Timestamp::new(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
  offset_minutes : Int,
) -> Timestamp raise SmsError {
  guard offset_minutes % 15 == 0 else {
    raise InvalidField("time zone must be a multiple of fifteen minutes")
  }
  let quarters = offset_minutes / 15
  let negative = quarters < 0
  let magnitude = if negative { -quarters } else { quarters }
  guard magnitude <= 79 else { raise InvalidField("time zone out of range") }
  let sign_bit = if negative { 0x08 } else { 0 }
  let tz_raw = ((magnitude / 10) & 0x7) | ((magnitude % 10) << 4) | sign_bit
  { year, month, day, hour, minute, second, tz_raw }
}

///|
/// Offset from UTC in minutes, positive east of Greenwich.
pub fn Timestamp::offset_minutes(self : Timestamp) -> Int {
  let quarters = ((self.tz_raw & 0x07) * 10) + ((self.tz_raw >> 4) & 0xF)
  if (self.tz_raw & 0x08) != 0 {
    -quarters * 15
  } else {
    quarters * 15
  }
}

///|
/// Reads one swapped-BCD pair: the low nibble holds the tens digit.
fn read_bcd(octets : ArrayView[Byte], pos : Int) -> Int {
  let byte = octets[pos].to_int()
  ((byte & 0xF) * 10) + ((byte >> 4) & 0xF)
}

///|
fn write_bcd(value : Int) -> Byte {
  (((value / 10) & 0xF) | (((value % 10) & 0xF) << 4)).to_byte()
}

///|
/// True when the calendar fields form a real date.
pub fn Timestamp::is_valid(self : Timestamp) -> Bool {
  let year = self.year
  if year < 1900 || year > 2089 {
    return false
  }
  if self.month < 1 || self.month > 12 {
    return false
  }
  if self.hour < 0 || self.hour > 23 || self.minute < 0 || self.minute > 59 {
    return false
  }
  if self.second < 0 || self.second > 59 {
    return false
  }
  let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let days = match self.month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    _ => if leap { 29 } else { 28 }
  }
  self.day >= 1 && self.day <= days
}

///|
/// Parses the seven timestamp octets at `pos`.
pub fn read_timestamp(octets : ArrayView[Byte], pos : Int) -> Timestamp raise SmsError {
  guard pos + 6 < octets.length() else { raise Truncated("timestamp") }
  {
    // The year is stored as an offset from 1900, not from 2000.
    year: 1900 + read_bcd(octets, pos),
    month: read_bcd(octets, pos + 1),
    day: read_bcd(octets, pos + 2),
    hour: read_bcd(octets, pos + 3),
    minute: read_bcd(octets, pos + 4),
    second: read_bcd(octets, pos + 5),
    tz_raw: octets[pos + 6].to_int(),
  }
}

///|
/// Serialises a timestamp to its seven octets.
pub fn Timestamp::to_octets(self : Timestamp) -> Array[Byte] raise SmsError {
  guard self.is_valid() else { raise InvalidField("timestamp out of range") }
  [
    write_bcd(self.year % 100), write_bcd(self.month), write_bcd(self.day),
    write_bcd(self.hour), write_bcd(self.minute), write_bcd(self.second),
    self.tz_raw.to_byte(),
  ]
}

///|
/// Formats the timestamp as `YYYY-MM-DDThh:mm:ss±hh:mm`.
pub fn Timestamp::to_display(self : Timestamp) -> String {
  let offset = self.offset_minutes()
  let sign = if offset < 0 { "-" } else { "+" }
  let magnitude = if offset < 0 { -offset } else { offset }
  "\{pad(self.year, 4)}-\{pad(self.month, 2)}-\{pad(self.day, 2)}T\{pad(self.hour, 2)}:\{pad(self.minute, 2)}:\{pad(self.second, 2)}\{sign}\{pad(magnitude / 60, 2)}:\{pad(magnitude % 60, 2)}"
}

///|
pub impl Show for Timestamp with fn to_string(self) {
  self.to_display()
}

///|
fn pad(value : Int, width : Int) -> String {
  let mut out = value.to_string()
  while out.length() < width {
    out = "0" + out
  }
  out
}
///|
/// Builds a timestamp for fixtures, panicking on an invalid argument.
pub fn timestamp_unchecked(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
  offset_minutes : Int,
) -> Timestamp {
  try Timestamp::new(year, month, day, hour, minute, second, offset_minutes) catch {
    _ => abort("invalid timestamp fixture")
  }
}
