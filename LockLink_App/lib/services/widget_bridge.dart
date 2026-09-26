import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_settings.dart';

/// Sends credentials only to the app's own native, protected widget storage.
class WidgetBridge {
  static const _channel = MethodChannel('com.locklink/widgets');
  static Future<void> _pending = Future<void>.value();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> synchronize(DeviceSettings settings) {
    if (!supported) return Future<void>.value();
    final next = _pending
        .catchError((Object _) {})
        .then((_) => _synchronize(settings));
    _pending = next;
    return next;
  }

  static Future<void> _synchronize(DeviceSettings settings) async {
    try {
      final address = await settings.loadAddress();
      final key = await settings.loadUnlockKey(address);
      await _channel.invokeMethod<void>('configure', {
        'address': address,
        'signingKey': key,
      });
    } catch (_) {
      // Do not leave a widget targeting a previously configured gate.
      try {
        await _channel.invokeMethod<void>('clear');
      } catch (_) {
        // Report the original synchronization failure to the UI.
      }
      rethrow;
    }
  }

  static Future<bool> requestPin() async =>
      supported && (await _channel.invokeMethod<bool>('requestPin') ?? false);
}
