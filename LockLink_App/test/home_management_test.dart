import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/terminal_service.dart';
import 'package:locklink/services/terminal_session.dart';
import 'package:locklink/screens/smart_home_screen.dart';
import 'package:locklink/screens/terminal_screen.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

Map<String, Object?> reply({bool window = true, bool added = false}) => {
  'version': 1,
  'boot': 'abc',
  'cursor': 1,
  'gap': false,
  'lines': [],
  'ok': true,
  'commissioned': true,
  'output': '',
  'pairing_code': '34970112332',
  'pairing_qr_payload': 'MT:Y.K9042C00KA0648G00',
  'pairing_mode': 'additional',
  'pairing_window_id': '1234567890abcdef',
  'pairing_window_open': window,
  'fabric_capacity': 5,
  'homes': [
    {
      'id': '0123456789abcdef',
      'index': 1,
      'vendor_id': 4937,
      'label': 'My home',
    },
    if (added)
      {'id': '1123456789abcdef', 'index': 2, 'vendor_id': 24582, 'label': ''},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'unlock_key:${DeviceSettings.defaultAddress}': 'a' * 64,
    }),
  );

  test(
    'terminal without a saved key explains setup and sends no requests',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = TerminalSession(
        DeviceSettings(preferences: MemoryPreferences()),
      );
      addTearDown(session.dispose);
      await http.runWithClient(
        session.start,
        () => MockClient((_) async => throw StateError('Unexpected request')),
      );
      expect(session.connected, isFalse);
      expect(session.error, 'Add a pairing key in Settings.');
    },
  );

  testWidgets('setup and check buttons stay enabled during background polls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var poll = Completer<http.Response>();
    final commands = <String>[];
    http.Response response(String command) {
      final data = reply();
      if (command != 'PAIR ADD') {
        data['pairing_code'] = null;
        data['pairing_qr_payload'] = null;
      }
      return http.Response(jsonEncode(data), 200);
    }

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeSetupScreen(
              settings: DeviceSettings(preferences: MemoryPreferences()),
              ecosystem: HomeEcosystem.apple,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        final setup = find.widgetWithText(FilledButton, 'Get sharing code');
        expect(tester.widget<FilledButton>(setup).onPressed, isNotNull);
        await tester.tap(setup);
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Getting code…'),
              )
              .onPressed,
          isNull,
        );
        poll.complete(response(''));
        await tester.pumpAndSettle();
        expect(commands.where((c) => c == 'PAIR ADD').length, 1);
        poll = Completer<http.Response>();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        final check = find.widgetWithText(FilledButton, 'Check pairing');
        expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
        await tester.tap(check);
        await tester.pump();
        expect(tester.widget<FilledButton>(check).onPressed, isNull);
        poll.complete(response(''));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('No new pairing detected yet.'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/challenge')) {
          return http.Response(
            '{"nonce":"00112233445566778899aabbccddeeff"}',
            200,
          );
        }
        commands.add(request.body);
        if (request.body.isEmpty) return poll.future;
        return response(request.body);
      }),
    );
  });

  for (final scenario in ['legacy', 'restart', 'concurrent']) {
    testWidgets('pairing check avoids false confirmation after $scenario', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var changed = false;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: HomeSetupScreen(
                settings: DeviceSettings(preferences: MemoryPreferences()),
                ecosystem: HomeEcosystem.apple,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (scenario != 'legacy') {
            await tester.tap(find.text('Get sharing code'));
            await tester.pumpAndSettle();
            changed = true;
          }
          await tester.ensureVisible(find.text('Check pairing'));
          await tester.tap(find.text('Check pairing'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Matter pairing detected.'), findsNothing);
          expect(
            find.textContaining(switch (scenario) {
              'legacy' => 'this does not confirm a new pairing',
              'restart' => 'Door restarted. Get a fresh code',
              _ => 'No new pairing detected yet.',
            }),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response(
              '{"nonce":"00112233445566778899aabbccddeeff"}',
              200,
            );
          }
          final data = reply(
            added:
                scenario == 'concurrent' &&
                (changed || request.body == 'PAIR ADD'),
          );
          if (scenario == 'restart' && changed) data['boot'] = 'def';
          if (request.body != 'PAIR ADD') {
            data['pairing_code'] = null;
            data['pairing_qr_payload'] = null;
          }
          if (scenario == 'legacy') {
            for (final key in [
              'homes',
              'fabric_capacity',
              'pairing_mode',
              'pairing_window_id',
              'pairing_window_open',
            ]) {
              data.remove(key);
            }
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
    });
  }

  testWidgets('rename and removal on one app sync to another app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var label = 'My home';
    var removed = false;
    final commands = <String>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: SmartHomeScreen(
                      settings: DeviceSettings(
                        preferences: MemoryPreferences(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('My home'), findsNWidgets(2));
        await tester.tap(find.byTooltip('Manage My home').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Family home');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Family home'), findsNWidgets(2));
        expect(commands.where((c) => c.startsWith('HOME NAME ')).length, 1);
        await tester.tap(find.byTooltip('Manage Family home').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove home'));
        await tester.pumpAndSettle();
        expect(find.text('Remove Family home?'), findsOneWidget);
        expect(removed, isFalse);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove home'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('Family home'), findsNothing);
        expect(find.text('Google Home · 2'), findsNWidgets(2));
        expect(commands.where((c) => c.startsWith('HOME REMOVE ')).length, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/challenge')) {
          return http.Response(
            '{"nonce":"00112233445566778899aabbccddeeff"}',
            200,
          );
        }
        commands.add(request.body);
        if (request.body.startsWith('HOME NAME ')) {
          final hex = request.body.split(' ').last;
          label = utf8.decode([
            for (var i = 0; i < hex.length; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ]);
        }
        if (request.body.startsWith('HOME REMOVE ')) removed = true;
        final data = reply(window: false, added: true);
        final homes = data['homes'] as List<Map<String, Object>>;
        if (removed) {
          homes.removeAt(0);
        } else {
          homes.first['label'] = label;
        }
        data['pairing_code'] = null;
        data['pairing_qr_payload'] = null;
        data['pairing_mode'] = null;
        return http.Response(jsonEncode(data), 200);
      }),
    );
  });

  testWidgets(
    'additional setup checks for a new home rather than existing pairing',
    (tester) async {
      var added = false;
      final commands = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: HomeSetupScreen(
                settings: DeviceSettings(preferences: MemoryPreferences()),
                ecosystem: HomeEcosystem.apple,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Get sharing code'));
          await tester.pumpAndSettle();
          expect(commands, contains('PAIR ADD'));
          await tester.ensureVisible(find.text('Check pairing'));
          await tester.tap(find.text('Check pairing'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('No new pairing detected yet.'),
            findsOneWidget,
          );
          added = true;
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Check pairing'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Matter pairing detected.'),
            findsOneWidget,
          );
          expect(find.text('Copy code'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response(
              '{"nonce":"00112233445566778899aabbccddeeff"}',
              200,
            );
          }
          commands.add(request.body);
          final data = reply(added: added);
          if (request.body != 'PAIR ADD') {
            data['pairing_code'] = null;
            data['pairing_qr_payload'] = null;
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
    },
  );

  testWidgets(
    'Terminal sends through a live poll and keeps a newly edited draft',
    (tester) async {
      final poll = Completer<http.Response>();
      final send = Completer<http.Response>();
      final commands = <String>[];
      http.Response response() {
        final data = reply(window: false);
        data['pairing_code'] = null;
        data['pairing_qr_payload'] = null;
        return http.Response(jsonEncode(data), 200);
      }

      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: TerminalScreen(
                settings: DeviceSettings(preferences: MemoryPreferences()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(commands, contains(''));
          await tester.enterText(find.byType(TextField), 'help');
          await tester.testTextInput.receiveAction(TextInputAction.send);
          await tester.pump();
          expect(commands.where((c) => c == 'HELP'), isEmpty);
          poll.complete(response());
          await tester.pump();
          await tester.pump();
          expect(commands.where((c) => c == 'HELP').length, 1);
          await tester.enterText(find.byType(TextField), 'STATUS');
          send.complete(response());
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'STATUS',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response(
              '{"nonce":"00112233445566778899aabbccddeeff"}',
              200,
            );
          }
          commands.add(request.body);
          if (request.body.isEmpty && !poll.isCompleted) return poll.future;
          if (request.body == 'HELP') return send.future;
          return response();
        }),
      );
    },
  );

  test('additional pairing requires explicit live-window metadata', () {
    final value = reply();
    final parsed = TerminalReply.fromJson(value);
    expect(parsed.pairingCode, '34970112332');
    expect(parsed.homes!.single.label, 'My home');
    expect(parsed.homes!.single.platform, 'Apple Home');
    expect(
      TerminalReply.fromJson({...value, 'pairing_window_open': false})
          .pairingCode,
      isNull,
    );
    expect(
      TerminalReply.fromJson({...value, 'pairing_mode': null}).pairingCode,
      isNull,
    );
    expect(
      () => TerminalReply.fromJson({
        ...value,
        'homes': [value['homes'], value['homes']],
      }),
      throwsFormatException,
    );
  });

  for (final reason in [
    'window closed',
    'home added',
    'code replaced',
    'background',
  ]) {
    test('additional code survives polling then hides on $reason', () async {
      var changed = false;
      await http.runWithClient(
        () async {
          final session = TerminalSession(
            DeviceSettings(preferences: MemoryPreferences()),
          );
          addTearDown(session.dispose);
          await session.start();
          await session.send('PAIR ADD');
          expect(session.pairingCode, '34970112332');
          await session.send('');
          expect(session.pairingCode, '34970112332');
          changed = true;
          if (reason == 'background') {
            session.setActive(false);
          } else {
            await session.send('');
          }
          expect(session.pairingCode, isNull);
          expect(session.pairingQrPayload, isNull);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response(
              '{"nonce":"00112233445566778899aabbccddeeff"}',
              200,
            );
          }
          final data = reply(
            window: !(changed && reason == 'window closed'),
            added: changed && reason == 'home added',
          );
          if (changed && reason == 'code replaced') {
            data['pairing_window_id'] = '2234567890abcdef';
          }
          if (request.body != 'PAIR ADD') {
            data['pairing_code'] = null;
            data['pairing_qr_payload'] = null;
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
    });
  }
}
