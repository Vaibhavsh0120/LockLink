import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceSettings {
  DeviceSettings({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _addressKey = 'device_address';
  static const _hapticsKey = 'haptic_feedback_enabled';
  static const _secureStorage = FlutterSecureStorage();
  final SharedPreferencesAsync _preferences;
  final Map<String, String> _webSessionKeys = {};

  Future<String?> loadAddress() => _preferences.getString(_addressKey);
  Future<void> saveAddress(String address) =>
      _preferences.setString(_addressKey, address);

  Future<bool> loadHapticsEnabled() async =>
      await _preferences.getBool(_hapticsKey) ?? true;
  Future<void> saveHapticsEnabled(bool enabled) =>
      _preferences.setBool(_hapticsKey, enabled);

  Future<String?> loadUnlockKey(String address) async {
    if (kIsWeb) return _webSessionKeys[address];
    return _secureStorage.read(key: 'unlock_key:$address');
  }

  Future<void> saveUnlockKey(String address, String key) async {
    final normalized = key.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('Use a 64-character hex pairing key');
    }
    if (kIsWeb) {
      _webSessionKeys[address] = normalized;
    } else {
      await _secureStorage.write(key: 'unlock_key:$address', value: normalized);
    }
  }

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
