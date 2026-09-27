/// Accept Matter's raw Base38 onboarding payload, never an image/webpage URL.
/// Invalid optional QR data must not prevent manual-code pairing.
String? matterPairingPayload(dynamic value) {
  if (value is! String ||
      value.length > 512 ||
      !RegExp(r'^MT:[0-9A-Z.\-]{19,}$').hasMatch(value)) {
    return null;
  }
  const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.';
  final data = value.substring(3);
  final bytes = <int>[];
  for (var offset = 0; offset < data.length; offset += 5) {
    final count = (data.length - offset).clamp(0, 5);
    final byteCount = switch (count) {
      5 => 3,
      4 => 2,
      2 => 1,
      _ => 0,
    };
    if (byteCount == 0) return null;
    var number = 0;
    for (var i = count - 1; i >= 0; i--) {
      number = number * 38 + alphabet.indexOf(data[offset + i]);
    }
    if (number >= (1 << (8 * byteCount))) return null;
    for (var i = 0; i < byteCount; i++) {
      bytes.add(number & 0xff);
      number >>= 8;
    }
  }
  // The fixed header is 11 bytes: version 0 and four reserved high bits.
  if (bytes.length < 11 || bytes[0] & 7 != 0 || bytes[10] & 0xf0 != 0) {
    return null;
  }
  return value;
}
