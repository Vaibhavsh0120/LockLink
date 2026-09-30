import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/app/locklink_app.dart';
import 'package:locklink/services/device_settings.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

void main() {
  testWidgets(
    'fresh relay setup reads status but cannot release without a key',
    (tester) async {
      const widgetChannel = MethodChannel('com.locklink/widgets');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        widgetChannel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          widgetChannel,
          null,
        ),
      );
      FlutterSecureStorage.setMockInitialValues({});
      final settings = DeviceSettings(preferences: MemoryPreferences());
      expect(
        await settings.loadPairingKey(DeviceSettings.defaultAddress),
        isEmpty,
      );
      var reads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(LockLinkApp(settings: settings));
          await tester.pumpAndSettle();
          expect(reads, greaterThan(0));
          expect(find.text('Add a pairing key in Settings.'), findsOneWidget);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/status');
          reads++;
          return http.Response(
            '{"online":true,"state":"locked","mode":"relay","armed":true}',
            200,
          );
        }),
      );
    },
  );
}
