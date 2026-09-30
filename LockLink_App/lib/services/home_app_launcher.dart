import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum HomeAppOpenResult { setup, opened, unavailable, unsupported }

/// Native handoff to a fixed home app, never an arbitrary URL or cloud endpoint.
abstract final class HomeAppLauncher {
  static const _channel = MethodChannel('com.locklink/home_apps');

  static bool supports(String ecosystem) =>
      !kIsWeb &&
      const ['apple', 'google', 'alexa'].contains(ecosystem) &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          (defaultTargetPlatform == TargetPlatform.android &&
              ecosystem != 'apple'));

  static Future<HomeAppOpenResult> open(
    String ecosystem, {
    String? pairingQr,
  }) async {
    if (!supports(ecosystem)) return HomeAppOpenResult.unsupported;
    try {
      final result = await _channel.invokeMethod<String>('open', {
        'ecosystem': ecosystem,
        // Only Android Play Services has a supported QR commissioning intent.
        // Other app launch URLs never contain pairing credentials.
        if (ecosystem == 'google' &&
            defaultTargetPlatform == TargetPlatform.android &&
            pairingQr != null)
          'pairingQr': pairingQr,
      });
      return switch (result) {
        'setup' => HomeAppOpenResult.setup,
        'opened' => HomeAppOpenResult.opened,
        _ => HomeAppOpenResult.unavailable,
      };
    } on PlatformException {
      return HomeAppOpenResult.unavailable;
    } on MissingPluginException {
      return HomeAppOpenResult.unavailable;
    }
  }
}
