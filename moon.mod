// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "chen333w/moon-sms-pdu"

version = "0.6.2"

readme = "README.mbt.md"

repository = "https://github.com/chen333w/moon-sms-pdu"

license = "Apache-2.0"

keywords = [
  "sms",
  "pdu",
  "gsm",
  "3gpp",
  "ts23040",
  "ts23038",
  "ucs2",
  "septet",
  "smsc",
  "ussd",
  "telecom",
]

preferred_target = "wasm"

description = "SMS PDU codec: GSM 7-bit, UCS-2, user data headers, concatenation, status reports and USSD."

warnings = "-implicit_impl_as_method-test_unqualified_package"
