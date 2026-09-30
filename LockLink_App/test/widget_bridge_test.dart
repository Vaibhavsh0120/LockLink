import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/widget_bridge.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.locklink/widgets');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'shares the derived key and saved address, not the pairing text',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final settings = DeviceSettings(preferences: MemoryPreferences());
      await settings.saveUnlockKey(DeviceSettings.defaultAddress, '1234');
      await WidgetBridge.synchronize(settings);
      expect(calls.single.method, 'configure');
      expect(calls.single.arguments, {
        'address': 'http://192.168.0.112',
        'signingKey':
            '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
      });
    },
  );

  test(
    'clears stale native credentials after setup fails and can recover',
    () async {
      final calls = <String>[];
      var fail = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'configure' && fail) {
          throw PlatformException(code: 'widget_setup');
        }
        return null;
      });
      final settings = DeviceSettings(preferences: MemoryPreferences());
      await settings.saveUnlockKey(DeviceSettings.defaultAddress, '1234');
      await expectLater(
        WidgetBridge.synchronize(settings),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['configure', 'clear']);
      fail = false;
      await WidgetBridge.synchronize(settings);
      expect(calls.last, 'configure');
    },
  );

  test(
    'an unset key clears stale widget access without configuring it',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await expectLater(
        WidgetBridge.synchronize(
          DeviceSettings(preferences: MemoryPreferences()),
        ),
        throwsA(isA<MissingPairingKeyException>()),
      );
      expect(calls, ['clear']);
    },
  );

  test('unsupported platforms do not call native widget APIs', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Unexpected native call'),
    );
    await WidgetBridge.synchronize(
      DeviceSettings(preferences: MemoryPreferences()),
    );
    expect(await WidgetBridge.requestPin(), isFalse);
  });
}
