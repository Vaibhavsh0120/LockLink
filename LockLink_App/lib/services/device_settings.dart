import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceSettings {
  DeviceSettings({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _addressKey = 'device_address';
  static const defaultAddress = 'http://192.168.0.112';
  static const _themeKey = 'theme_mode';
  static const _hapticsKey = 'haptic_feedback_enabled';
  static const _secureStorage = FlutterSecureStorage();
  final SharedPreferencesAsync _preferences;
  final Map<String, String> _webSessionKeys = {};

  Future<String> loadAddress() async =>
      await _preferences.getString(_addressKey) ?? defaultAddress;
  Future<void> saveAddress(String address) =>
      _preferences.setString(_addressKey, address);

  Future<bool> loadHapticsEnabled() async =>
      await _preferences.getBool(_hapticsKey) ?? true;
  Future<void> saveHapticsEnabled(bool enabled) =>
      _preferences.setBool(_hapticsKey, enabled);

  Future<ThemeMode> loadThemeMode() async {
    return switch (await _preferences.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _preferences.setString(_themeKey, mode.name);

  Future<String> loadPairingKey(String address) async {
    final saved = kIsWeb
        ? _webSessionKeys[address]
        : await _secureStorage.read(key: 'unlock_key:$address');
    return saved ?? '';
  }

  Future<String> loadUnlockKey(String address) async {
    final raw = await loadPairingKey(address);
    if (raw.trim().isEmpty) throw const MissingPairingKeyException();
    return signingKey(raw);
  }

  static String signingKey(String raw) {
    final value = raw.trim();
    if (value.length < 4 || value.length > 64) {
      throw const FormatException('Use 4 to 64 characters');
    }
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return value.toLowerCase();
    }
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<void> saveUnlockKey(String address, String key) async {
    final normalized = key.trim();
    signingKey(normalized); // Validate before storing the user-facing value.
    if (kIsWeb) {
      _webSessionKeys[address] = normalized;
    } else {
      await _secureStorage.write(key: 'unlock_key:$address', value: normalized);
    }
  }

  static String? normalizeAddress(String raw) {
    final input = raw.trim();
    final value = input.contains('://') ? input : 'http://$input';
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
    try {
      if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
    } on FormatException {
      return null;
    }
    final segments = host.split('.');
    final octets = host.split('.').map(int.tryParse).toList();
    final validIpv4 =
        octets.length == 4 &&
        octets.every((part) => part != null && part >= 0 && part <= 255) &&
        List.generate(
          4,
          (i) => octets[i].toString() == segments[i],
        ).every((v) => v);
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

class MissingPairingKeyException implements Exception {
  const MissingPairingKeyException();
  static const message = 'Add a pairing key in Settings.';

  @override
  String toString() => message;
}
