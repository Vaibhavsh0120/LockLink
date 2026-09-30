import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/app/app_theme.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/terminal_session.dart';
import 'package:locklink/widgets/pairing_code_display.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

const qrPayload = 'MT:Y.K9042C00KA0648G00';
http.Response response(
  String command, {
  String boot = 'abc',
  Object? qr = qrPayload,
}) => http.Response(
  jsonEncode({
    'version': 1,
    'boot': boot,
    'cursor': 1,
    'gap': false,
    'lines': [],
    'output': command == 'PAIR' ? 'Code: 34970112332' : '',
    'ok': true,
    'commissioned': false,
    'pairing_code': command == 'PAIR' ? '34970112332' : null,
    'pairing_qr_payload': command == 'PAIR' ? qr : null,
  }),
  200,
);

http.Response challenge() =>
    http.Response('{"nonce":"00112233445566778899aabbccddeeff"}', 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'unlock_key:${DeviceSettings.defaultAddress}': 'a' * 64,
    }),
  );

  test(
    'a PAIR reply started before backgrounding cannot restore codes',
    () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      await http.runWithClient(
        () async {
          final session = TerminalSession(
            DeviceSettings(preferences: MemoryPreferences()),
          );
          addTearDown(session.dispose);
          await session.start();
          final request = session.send('PAIR');
          await requested.future;
          session.setActive(false);
          session.setActive(true);
          pending.complete(response('PAIR'));
          await request;
          expect(session.pairingCode, isNull);
          expect(session.pairingQrPayload, isNull);
          expect(session.latest?.pairingQrPayload, isNull);
          expect(session.lines.join('\n'), isNot(contains(qrPayload)));
          expect(session.lines.join('\n'), isNot(contains('34970112332')));
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) return challenge();
          if (request.body == 'PAIR') {
            requested.complete();
            return pending.future;
          }
          return response(request.body);
        }),
      );
    },
  );

  for (final reason in ['disconnect', 'reboot']) {
    testWidgets('open QR is removed on $reason', (tester) async {
      var changed = false;
      await http.runWithClient(
        () async {
          final session = TerminalSession(
            DeviceSettings(preferences: MemoryPreferences()),
          );
          await session.start();
          await session.send('PAIR');
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showPairingQr(context, session),
                    child: const Text('Show'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Show'));
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsOneWidget);
          changed = true;
          await session.send('');
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsNothing);
          expect(find.byType(Dialog), findsNothing);
          expect(session.pairingCode, isNull);
          expect(session.pairingQrPayload, isNull);
          expect(session.latest?.pairingQrPayload, isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        },
        () => MockClient((request) async {
          if (changed && reason == 'disconnect') {
            throw http.ClientException('offline');
          }
          if (request.url.path.endsWith('/challenge')) return challenge();
          return response(request.body, boot: changed ? 'def' : 'abc');
        }),
      );
    });
  }

  for (final qr in [null, 'https://example.com/qr']) {
    testWidgets('manual pairing and copy work when QR is $qr', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await http.runWithClient(
        () async {
          final session = TerminalSession(
            DeviceSettings(preferences: MemoryPreferences()),
          );
          await session.start();
          await session.send('PAIR');
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PairingCodeDisplay(session: session),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsNothing);
          expect(
            find.text('QR unavailable. Use the setup code.'),
            findsOneWidget,
          );
          expect(find.text('34970112332'), findsOneWidget);
          await tester.tap(find.text('Copy code'));
          await tester.pumpAndSettle();
          expect(copied, '34970112332');
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        },
        () => MockClient(
          (request) async => request.url.path.endsWith('/challenge')
              ? challenge()
              : response(request.body, qr: qr),
        ),
      );
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('QR stays white and dialog fits large text in $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
      });
      await http.runWithClient(
        () async {
          final session = TerminalSession(
            DeviceSettings(preferences: MemoryPreferences()),
          );
          await session.start();
          await session.send('PAIR');
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: PairingCodeDisplay(session: session),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final qr = tester.widget<QrImageView>(find.byType(QrImageView));
          expect(qr.backgroundColor, Colors.white);
          expect(qr.eyeStyle.color, Colors.black);
          expect(qr.dataModuleStyle.color, Colors.black);
          expect(qr.size, lessThanOrEqualTo(260));
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Enlarge QR'));
          await tester.tap(find.text('Enlarge QR'));
          await tester.pumpAndSettle();
          final enlargedQr = tester.widget<QrImageView>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(QrImageView),
            ),
          );
          expect(enlargedQr.size, greaterThan(qr.size!));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close pairing QR'));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          session.dispose();
        },
        () => MockClient(
          (request) async => request.url.path.endsWith('/challenge')
              ? challenge()
              : response(request.body),
        ),
      );
    });
  }
}
