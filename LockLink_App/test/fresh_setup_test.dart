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
    'fresh relay setup uses defaults and only releases after a tap',
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
        'd489653731bf3aeec85cca136a511294c329106e20a0b2627adc2f180146a507',
      );
      expect(await settings.loadAddress(), 'http://192.168.0.112');
      expect(
        await settings.loadUnlockKey(DeviceSettings.defaultAddress),
        'd489653731bf3aeec85cca136a511294c329106e20a0b2627adc2f180146a507',
      );
      var reads = 0;
      final requests = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(LockLinkApp(settings: settings));
          await tester.pumpAndSettle();
          expect(reads, greaterThan(0));
          expect(find.text('Add a pairing key in Settings.'), findsNothing);
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNotNull,
          );
          expect(requests, isNot(contains('/unlock')));
          expect(requests, contains('/challenge'));
          requests.clear();
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(
            requests.first,
            '/unlock',
          ); // No challenge request before POST.
          expect(requests.where((path) => path == '/unlock').length, 1);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          requests.add(request.url.path);
          if (request.url.path == '/unlock') {
            expect(request.method, 'POST');
            expect(request.headers['X-LockLink-Nonce'], 'a' * 32);
            return http.Response(
              '{"success":true,"state":"unlocking","duration_ms":1000}',
              200,
            );
          }
          expect(request.method, 'GET');
          if (request.url.path == '/challenge') {
            return http.Response('{"nonce":"${'a' * 32}"}', 200);
          }
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
