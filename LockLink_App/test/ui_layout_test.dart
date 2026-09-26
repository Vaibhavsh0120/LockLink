import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/app/locklink_app.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/widgets/door_control_card.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

void main() {
  for (final size in [const Size(320, 740), const Size(1440, 960)]) {
    testWidgets('home and settings fit $size with large text', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      const channel = MethodChannel('com.locklink/widgets');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      FlutterSecureStorage.setMockInitialValues({});
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            LockLinkApp(
              settings: DeviceSettings(preferences: MemoryPreferences()),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Device settings'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Dark'));
          await tester.tap(find.text('Dark'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
        () => MockClient(
          (_) async => http.Response('{"online":true,"state":"locked"}', 200),
        ),
      );
    });
  }

  testWidgets('unlock is available only when online, ready and idle', (
    tester,
  ) async {
    var commands = 0;
    for (final state in [
      (false, true, false),
      (true, false, false),
      (true, true, true),
      (true, true, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoorControlCard(
              online: state.$1,
              ready: state.$2,
              active: state.$3,
              stateLabel: 'Device status',
              statusText: 'Connection status',
              helperText: null,
              onUnlock: () => commands++,
            ),
          ),
        ),
      );
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed != null, state.$1 && state.$2 && !state.$3);
      if (button.onPressed != null) await tester.tap(find.byType(FilledButton));
      expect(tester.takeException(), isNull);
    }
    expect(commands, 1);
  });
}
