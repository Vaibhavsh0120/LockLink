import 'package:shared_preferences/shared_preferences.dart';

class DeviceSettings {
  DeviceSettings({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _addressKey = 'device_address';
  final SharedPreferencesAsync _preferences;

  Future<String?> loadAddress() => _preferences.getString(_addressKey);
  Future<void> saveAddress(String address) =>
      _preferences.setString(_addressKey, address);

  static String? normalizeAddress(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final octets = host.split('.').map(int.tryParse).toList();
    final validIpv4 =
        octets.length == 4 &&
        octets.every((part) => part != null && part >= 0 && part <= 255);
    final isPrivateIpv4 =
        validIpv4 &&
        (octets[0] == 10 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31));
    final isLocal =
        host == 'localhost' || host.endsWith('.local') || isPrivateIpv4;
    if (!isLocal) return null;
    return uri.replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
  }
}
