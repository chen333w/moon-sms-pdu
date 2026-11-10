///|
/// A TP-SCTS / TP-VP-absolute timestamp: six swapped-BCD fields followed by a
/// time zone expressed in quarter hours.
///
/// The time zone is kept as the raw octet it arrived in. That looks pedantic
/// until you meet a real SMSC: the sign lives in bit 3, so `0x08` means
/// "zero offset, negative", which a plain integer offset would silently rewrite
/// to `0x00`. Keeping the octet makes re-encoding byte for byte identical.
pub(all) struct Timestamp {
  year : Int32
  month : Int32
  day : Int32
  hour : Int32
  minute : Int32
  second : Int32
  tz_raw : Int32
} derive(Eq, @debug.Debug)

///|
/// Builds a timestamp from calendar fields and an offset in minutes. The offset
/// must be a whole number of quarter hours.
pub fn Timestamp::new(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
  offset_minutes : Int32,
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
  { year, month, day, hour, minute, second, tz_raw, }
}

///|
/// Offset from UTC in minutes, positive east of Greenwich.
pub fn Timestamp::offset_minutes(self : Timestamp) -> Int32 {
  let quarters = (self.tz_raw & 0x07) * 10 + ((self.tz_raw >> 4) & 0xF)
  if (self.tz_raw & 0x08) != 0 {
    -quarters * 15
  } else {
    quarters * 15
  }
}

///|
/// Reads one swapped-BCD pair: the low nibble holds the tens digit.
fn read_bcd(octets : ArrayView[Byte], pos : Int32) -> Int32 {
  let byte = octets[pos].to_int()
  (byte & 0xF) * 10 + ((byte >> 4) & 0xF)
}

///|
fn write_bcd(value : Int32) -> Byte {
  (((value / 10) & 0xF) | (((value % 10) & 0xF) << 4)).to_byte()
}

///|
/// True when the calendar fields form a real date.
pub fn Timestamp::is_valid(self : Timestamp) -> Bool {
  let year = self.year
  // The wire format stores two digits, so the representable range has to be
  // one century. Reading and writing must agree on which, or a timestamp
  // survives a decode and then comes back a hundred years off.
  if year < 2000 || year > 2099 {
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
pub fn read_timestamp(
  octets : ArrayView[Byte],
  pos : Int32,
) -> Timestamp raise SmsError {
  guard pos + 6 < octets.length() else { raise Truncated("timestamp") }
  {
    year: 2000 + read_bcd(octets, pos),
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
    write_bcd(self.year - 2000),
    write_bcd(self.month),
    write_bcd(self.day),
    write_bcd(self.hour),
    write_bcd(self.minute),
    write_bcd(self.second),
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
fn pad(value : Int32, width : Int32) -> String {
  let mut out = value.to_string()
  while out.length() < width {
    out = "0" + out
  }
  out
}

///|
/// Builds a timestamp for fixtures, panicking on an invalid argument.
pub fn timestamp_unchecked(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
  offset_minutes : Int32,
) -> Timestamp {
  Timestamp::new(year, month, day, hour, minute, second, offset_minutes) catch {
    _ => abort("invalid timestamp fixture")
  }
}

///|
/// Days since the Unix epoch for a date in the proleptic Gregorian calendar.
///
/// Howard Hinnant's days_from_civil, which avoids a lookup table and gets the
/// leap-year century rules right without branching on them.
fn days_from_civil(year : Int32, month : Int32, day : Int32) -> Int32 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// Inverse of `days_from_civil`.
fn civil_from_days(days : Int32) -> (Int32, Int32, Int32) {
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

///|
/// Seconds since the Unix epoch, interpreting the timestamp as UTC.
///
/// The wire format carries a time zone but no daylight-saving rules, so this is
/// the local clock plus the stated offset, nothing more.
pub fn Timestamp::to_unix(self : Timestamp) -> Int64 {
  let days = days_from_civil(self.year, self.month, self.day)
  // These add; using `|` here would merge the fields bitwise and quietly
  // produce a wrong instant whenever two of them share a set bit.
  let seconds = days.to_int64() * 86400L +
    self.hour.to_int64() * 3600L +
    self.minute.to_int64() * 60L +
    self.second.to_int64()
  seconds - self.offset_minutes().to_int64() * 60L
}

///|
/// Builds a timestamp from seconds since the Unix epoch, in UTC.
pub fn Timestamp::from_unix(seconds : Int64) -> Timestamp raise SmsError {
  let days = floor_div(seconds, 86400L)
  let rest = seconds - days * 86400L
  let (year, month, day) = civil_from_days(days.to_int())
  let hour = (rest / 3600L).to_int()
  let minute = (rest % 3600L / 60L).to_int()
  let second = (rest % 60L).to_int()
  Timestamp::new(year, month, day, hour, minute, second, 0)
}

///|
fn floor_div(value : Int64, divisor : Int64) -> Int64 {
  let quotient = value / divisor
  if value % divisor != 0 && (value < 0L) != (divisor < 0L) {
    quotient - 1L
  } else {
    quotient
  }
}

///|
/// Signed difference in seconds, this timestamp minus `other`.
pub fn Timestamp::seconds_since(self : Timestamp, other : Timestamp) -> Int64 {
  self.to_unix() - other.to_unix()
}

///|
/// True when the timestamp lies before `other`.
pub fn Timestamp::is_before(self : Timestamp, other : Timestamp) -> Bool {
  self.to_unix() < other.to_unix()
}

///|
/// Adds a number of seconds, keeping the time zone octet as it was.
pub fn Timestamp::add_seconds(
  self : Timestamp,
  seconds : Int64,
) -> Timestamp raise SmsError {
  let shifted = Timestamp::from_unix(self.to_unix() + seconds)
  { ..shifted, tz_raw: self.tz_raw, }
}

///|
/// Renders the timestamp as RFC 3339 with the offset written out, which is what
/// most log pipelines expect.
pub fn Timestamp::to_rfc3339(self : Timestamp) -> String {
  let offset = self.offset_minutes()
  let sign = if offset < 0 { "-" } else { "+" }
  let magnitude = if offset < 0 { -offset } else { offset }
  "\{pad(self.year, 4)}-\{pad(self.month, 2)}-\{pad(self.day, 2)}T\{pad(self.hour, 2)}:\{pad(self.minute, 2)}:\{pad(self.second, 2)}\{sign}\{pad(magnitude / 60, 2)}:\{pad(magnitude % 60, 2)}"
}
