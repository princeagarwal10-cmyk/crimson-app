import 'dart:convert';

import 'customer_account_rules.dart';

/// Auth uses a private synthetic email address, but customers type only the
/// user ID given to them by the admin. Existing email logins remain supported.
String customerLoginEmail(String userIdOrEmail) {
  final value = userIdOrEmail.trim();
  if (value.contains('@')) return value;
  final normalized = normalizeCustomerUserId(value);
  final error = validateCustomerUserId(normalized);
  if (error != null) throw FormatException(error);
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  var buffer = 0;
  var bits = 0;
  final encoded = StringBuffer();
  for (final byte in utf8.encode(normalized)) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      encoded.write(alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) encoded.write(alphabet[(buffer << (5 - bits)) & 31]);
  return 'u$encoded@users.mycrimson.in';
}
