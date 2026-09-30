import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locklink/services/home_app_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.locklink/home_apps');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'Google Android handoff sends QR only to the native setup bridge',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.arguments['ecosystem'] == 'google' ? 'setup' : 'opened';
      });
      expect(
        await HomeAppLauncher.open(
          'google',
          pairingQr: 'MT:Y.K9042C00KA0648G00',
        ),
        HomeAppOpenResult.setup,
      );
      expect(calls.single.arguments, {
        'ecosystem': 'google',
        'pairingQr': 'MT:Y.K9042C00KA0648G00',
      });
      expect(
        await HomeAppLauncher.open('alexa', pairingQr: 'private'),
        HomeAppOpenResult.opened,
      );
      expect(calls.last.arguments, {'ecosystem': 'alexa'});
      expect(
        await HomeAppLauncher.open('apple'),
        HomeAppOpenResult.unsupported,
      );
      expect(
        await HomeAppLauncher.open('unknown'),
        HomeAppOpenResult.unsupported,
      );
      expect(calls.length, 2);
    },
  );

  test(
    'iOS URLs do not receive secrets and failures permit manual setup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.arguments, {'ecosystem': 'apple'});
        return 'unavailable';
      });
      expect(
        await HomeAppLauncher.open('apple', pairingQr: 'private'),
        HomeAppOpenResult.unavailable,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'blocked'),
      );
      expect(
        await HomeAppLauncher.open('google'),
        HomeAppOpenResult.unavailable,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        await HomeAppLauncher.open('google'),
        HomeAppOpenResult.unsupported,
      );
    },
  );
}
