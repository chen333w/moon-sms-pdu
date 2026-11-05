///|
/// Well-known application ports, 3GPP TS 23.040 §9.2.3.24.5 and the Open Mobile
/// Alliance assignments that ride on it.
///
/// Two messages to the same number mean different things depending on this
/// number: 2948 is a WAP push and has to be handed to the browser, 4996 is
/// device management and must not be. A codec that decodes the text and drops
/// the port has thrown away the only thing that said what to do with it.
pub(all) enum ApplicationPort {
  /// WAP push, 16-bit ports 2948 receiving from 9200..9203.
  WapPush
  /// Wireless application protocol session, 8-bit.
  WapSession
  /// OMA device management, 16-bit.
  DeviceManagement
  /// OMA client provisioning.
  ClientProvisioning
  /// Multimedia messaging notification.
  MmsNotification
  /// Over-the-air SIM update, short ports.
  SimUpdate
  /// Anything else, kept as the pair it arrived as.
  Other(Int32, Int32)
} derive(Eq, @debug.Debug)

///|
/// Names the application a port pair belongs to.
///
/// The destination port decides: the source is the sender's own number and
/// varies between implementations.
pub fn classify_ports(ports : Ports) -> ApplicationPort {
  let dest = ports.destination
  let src = ports.source
  // Order matters: 2948 is shared, so the narrower assignment is tested first.
  if dest == 2948 && src == 9202 {
    MmsNotification
  } else if dest == 2948 {
    WapPush
  } else if dest == 9200 && src >= 9200 && src <= 9203 {
    WapSession
  } else if dest == 4996 || dest == 4988 {
    DeviceManagement
  } else if dest == 4995 || dest == 4987 {
    ClientProvisioning
  } else if dest == 1600 {
    SimUpdate
  } else {
    Other(dest, src)
  }
}

///|
/// Reads the application out of a decoded delivery, when it carries one.
pub fn SmsDeliver::application(self : SmsDeliver) -> ApplicationPort? {
  match self.header {
    Some(header) =>
      match header.ports() {
        Some(ports) => Some(classify_ports(ports))
        None => None
      }
    None => None
  }
}

///|
/// Builds a delivery that goes to an application instead of the inbox.
///
/// The payload is eight-bit, because these protocols define their own binary
/// envelopes and running the bytes through a character encoding would corrupt
/// them.
pub fn SmsDeliver::to_application(
  originating : Address,
  ports : Ports,
  payload : Array[Byte],
) -> SmsDeliver raise SmsError {
  let deliver = {
    ..SmsDeliver::new(originating, "", encoding=EightBit),
    payload,
    header: Some(ports_header(ports)),
  }
  deliver
}

///|
/// Encodes an application-directed delivery. The header and the payload share
/// the user data field, so this is the path that has to be right.
pub fn application_to_octets(
  deliver : SmsDeliver,
) -> Array[Byte] raise SmsError {
  deliver.to_octets()
}

///|
pub impl Show for ApplicationPort with fn to_string(self) {
  match self {
    WapPush => "wap push"
    WapSession => "wap session"
    DeviceManagement => "device management"
    ClientProvisioning => "client provisioning"
    MmsNotification => "mms notification"
    SimUpdate => "sim update"
    Other(dest, src) => "port \{dest} from \{src}"
  }
}
