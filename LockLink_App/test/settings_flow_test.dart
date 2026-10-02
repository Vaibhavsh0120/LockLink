import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/app/locklink_app.dart';
import 'package:locklink/screens/settings_screen.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'settings applies themes and saves explicitly entered credentials',
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
      final preferences = MemoryPreferences();
      final settings = DeviceSettings(preferences: preferences);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await http.runWithClient(
        () async {
          await tester.pumpWidget(LockLinkApp(settings: settings));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Device settings'));
          await tester.pumpAndSettle();
          expect(find.text('Terminal'), findsNothing);
          expect(find.text('Smart home setup'), findsNothing);
          expect(find.text('Device tools'), findsNothing);

          final fields = find.byType(TextFormField);
          expect(
            tester.widget<TextFormField>(fields.at(0)).controller!.text,
            '192.168.0.112',
          );
          expect(
            tester.widget<TextFormField>(fields.at(1)).controller!.text,
            'd489653731bf3aeec85cca136a511294c329106e20a0b2627adc2f180146a507',
          );
          await tester.tap(find.byTooltip('Show pairing key'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText).at(1))
                .obscureText,
            isFalse,
          );

          for (final entry in {
            'Dark': ThemeMode.dark,
            'Light': ThemeMode.light,
            'System': ThemeMode.system,
          }.entries) {
            await tester.ensureVisible(find.text(entry.key));
            await tester.tap(find.text(entry.key));
            await tester.pumpAndSettle();
            expect(
              tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
              entry.value,
            );
            expect(
              await DeviceSettings(preferences: preferences).loadThemeMode(),
              entry.value,
            );
            expect(find.byType(SettingsScreen), findsOneWidget);
          }

          await tester.ensureVisible(fields.at(0));
          await tester.enterText(fields.at(0), '192.168.0.113');
          await tester.enterText(fields.at(1), '5678');
          await tester.ensureVisible(find.text('Save device'));
          await tester.tap(find.text('Save device'));
          await tester.pumpAndSettle();
          expect(find.byType(SettingsScreen), findsNothing);
          expect(await settings.loadAddress(), 'http://192.168.0.113');
          expect(await settings.loadPairingKey('http://192.168.0.113'), '5678');

          await tester.tap(find.byTooltip('Device settings'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextFormField>(fields.at(0)).controller!.text,
            '192.168.0.113',
          );
          expect(
            tester.widget<TextFormField>(fields.at(1)).controller!.text,
            '5678',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
        () => MockClient(
          (_) async => http.Response('{"online":true,"state":"locked"}', 200),
        ),
      );
    },
  );
}
