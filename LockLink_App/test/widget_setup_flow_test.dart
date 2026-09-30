import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/app_haptics.dart';
import 'package:locklink/screens/settings_screen.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

void main() {
  const channel = MethodChannel('com.locklink/widgets');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  testWidgets('iOS setup explains signing failure and recovers after retry', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'unlock_key:${DeviceSettings.defaultAddress}': 'a' * 64,
    });
    var failureCode = 'widget_app_group';
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'configure' && failureCode.isNotEmpty) {
        throw PlatformException(code: failureCode, message: 'private detail');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final theme = ValueNotifier(ThemeMode.light);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: DeviceSettings(preferences: MemoryPreferences()),
          haptics: AppHaptics(),
          themeMode: theme,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set up widgets'));
    await tester.tap(find.text('Set up widgets'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This installation cannot share widget settings.'),
      findsOneWidget,
    );
    expect(find.textContaining('signing tool'), findsOneWidget);
    expect(find.textContaining('private detail'), findsNothing);
    expect(calls, ['configure', 'clear']);

    failureCode = 'widget_locked';
    await tester.tap(find.text('Set up widgets'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unlock your iPhone, then tap Set up widgets again.'),
      findsOneWidget,
    );
    expect(find.textContaining('signing tool'), findsNothing);

    failureCode = '';
    await tester.tap(find.text('Set up widgets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Widget settings updated.'), findsOneWidget);
    expect(calls.last, 'requestPin');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
