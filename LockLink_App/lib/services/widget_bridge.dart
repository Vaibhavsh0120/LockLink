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

  /// Translate known native failure codes; never display raw platform details.
  static String setupFailureMessage(Object error) {
    if (error is MissingPluginException) {
      return 'Widget support is missing from this app build. '
          'Install the latest full LockLink app, then set up widgets again.';
    }
    if (error is PlatformException) {
      switch (error.code) {
        case 'widget_extension_missing':
          return 'This installation is missing the LockLink widget. '
              'Reinstall the full app and keep its widget extension '
              'when your signing tool asks.';
        case 'widget_app_group':
        case 'widget_keychain_access':
          return 'This installation cannot share widget settings. '
              'Reinstall the app and widget with the same shared App Group '
              'enabled in your signing tool.';
        case 'widget_locked':
          return 'Unlock your iPhone, then tap Set up widgets again.';
        case 'widget_settings':
          return 'Check and save your device address and pairing key, '
              'then tap Set up widgets again.';
      }
    }
    return 'Could not save widget settings. Tap Set up widgets to retry. '
        'If this keeps happening, update LockLink and try again.';
  }
}
