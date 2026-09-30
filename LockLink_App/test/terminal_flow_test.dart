import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/app/app_theme.dart';
import 'package:locklink/screens/smart_home_screen.dart';
import 'package:locklink/screens/terminal_screen.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'settings_flow_test.dart' show MemoryPreferences;

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_TERMINAL')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/terminal-preview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_TERMINAL')) return;
    const fontDir = String.fromEnvironment('PREVIEW_FONT_DIR');
    // Substitute Roboto for Apple's system font in Windows test captures.
    for (final family in [
      'Roboto',
      'monospace',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      '.AppleSystemUIFont',
      '.SF Pro Text',
      '.SF Pro Display',
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          File('$fontDir/roboto-regular.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File('$fontDir/materialicons-regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
  });
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'unlock_key:${DeviceSettings.defaultAddress}': 'a' * 64,
    }),
  );
  http.Response reply(String command, {bool paired = false}) => http.Response(
    jsonEncode({
      'version': 1,
      'boot': 'abc',
      'cursor': 1,
      'gap': false,
      'lines': <Object>[],
      'ok': true,
      'commissioned': paired,
      'pairing_code': command == 'PAIR' && !paired ? '34970112332' : null,
      'pairing_qr_payload': command == 'PAIR' && !paired
          ? 'MT:Y.K9042C00KA0648G00'
          : null,
      'output': command == 'PAIR'
          ? (paired ? 'Already paired.' : 'Code: 34970112332')
          : command == 'STATUS'
          ? 'Wi-Fi: 192.168.0.111\nMatter: ${paired ? 'paired' : 'not paired'}\nOutput: LED; armed: yes\nRelease: inactive'
          : '',
    }),
    200,
  );

  for (final terminal in [false, true]) {
    testWidgets(
      '${terminal ? 'Terminal' : 'Setup'} waits for device and recovers without a queued command',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var reachable = false;
        final commands = <String>[];
        await http.runWithClient(
          () async {
            final settings = DeviceSettings(preferences: MemoryPreferences());
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.build(Brightness.dark),
                  home: terminal
                      ? TerminalScreen(settings: settings)
                      : HomeSetupScreen(
                          settings: settings,
                          ecosystem: HomeEcosystem.apple,
                        ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final connectionError = find.text(
              'Cannot reach device. Check power, Wi-Fi and address.',
            );
            expect(connectionError, findsOneWidget);
            expect(
              tester.widget<Text>(connectionError).style?.color,
              AppTheme.build(Brightness.dark).colorScheme.error,
            );
            await capture(
              tester,
              terminal ? 'terminal-offline' : 'setup-offline',
            );
            if (terminal) {
              expect(
                tester
                    .widget<IconButton>(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is IconButton &&
                            widget.tooltip == 'Send command',
                      ),
                    )
                    .onPressed,
                isNull,
              );
            } else {
              expect(
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Get setup code'),
                    )
                    .onPressed,
                isNull,
              );
              expect(find.text('Retry connection'), findsOneWidget);
            }
            reachable = true;
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpAndSettle();
            expect(commands, ['']);
            if (terminal) {
              expect(
                tester
                    .widget<IconButton>(
                      find.byWidgetPredicate(
                        (widget) =>
                            widget is IconButton &&
                            widget.tooltip == 'Send command',
                      ),
                    )
                    .onPressed,
                isNotNull,
              );
            } else {
              expect(
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Get setup code'),
                    )
                    .onPressed,
                isNotNull,
              );
            }
            expect(find.byType(QrImageView), findsNothing);
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            if (!reachable) throw http.ClientException('device off');
            if (request.url.path.endsWith('/challenge')) {
              return http.Response(
                '{"nonce":"00112233445566778899aabbccddeeff"}',
                200,
              );
            }
            commands.add(request.body);
            return reply(request.body);
          }),
        );
      },
    );
  }

  for (final (ecosystem, platform, size) in [
    (HomeEcosystem.apple, TargetPlatform.iOS, const Size(390, 844)),
    (HomeEcosystem.google, TargetPlatform.android, const Size(390, 844)),
    (HomeEcosystem.alexa, TargetPlatform.iOS, const Size(834, 1112)),
  ]) {
    testWidgets('${ecosystem.label} launch has a readable manual fallback', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      const channel = MethodChannel('com.locklink/home_apps');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'unavailable';
      });
      addTearDown(() async {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await tester.binding.setSurfaceSize(null);
      });
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(Brightness.dark),
                home: HomeSetupScreen(
                  settings: DeviceSettings(preferences: MemoryPreferences()),
                  ecosystem: ecosystem,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await capture(tester, 'home-launch-${ecosystem.name}-initial');
          await tester.tap(find.text('Get setup code'));
          await tester.pumpAndSettle();
          final launch = find.text('Open ${ecosystem.label}');
          await tester.ensureVisible(launch);
          await tester.tap(launch);
          await tester.pumpAndSettle();
          expect(calls.length, 1);
          expect(calls.single.arguments, {
            'ecosystem': ecosystem.name,
            if (platform == TargetPlatform.android)
              'pairingQr': 'MT:Y.K9042C00KA0648G00',
          });
          final error = find.textContaining(
            'Could not open ${ecosystem.label}.',
          );
          expect(error, findsOneWidget);
          expect(
            tester.widget<Text>(error).style?.color,
            AppTheme.build(Brightness.dark).colorScheme.error,
          );
          await tester.ensureVisible(error);
          await capture(tester, 'home-launch-${ecosystem.name}-fallback');
          expect(find.text('Check pairing'), findsOneWidget);
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
          return reply(request.body);
        }),
      );
    }, variant: TargetPlatformVariant({platform}));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'home app choices stay separate and responsive in $brightness',
      (tester) async {
        for (final size in [
          const Size(390, 844),
          const Size(1440, 960),
          const Size(320, 740),
        ]) {
          await tester.binding.setSurfaceSize(size);
          tester.platformDispatcher.textScaleFactorTestValue = size.width == 320
              ? 2
              : 1;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(brightness),
                home: SmartHomeScreen(
                  settings: DeviceSettings(preferences: MemoryPreferences()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final apple = tester.getRect(
            find.widgetWithText(ListTile, 'Apple Home'),
          );
          final google = tester.getRect(
            find.widgetWithText(ListTile, 'Google Home'),
          );
          expect(google.top - apple.bottom, greaterThanOrEqualTo(12));
          expect(apple.width, lessThanOrEqualTo(600));
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'home-picker-${brightness.name}-${size.width.toInt()}',
          );
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(1440, 960)]) {
    testWidgets('terminal sends typed commands and pauses offscreen at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final commands = <String>[];
      final settings = DeviceSettings(preferences: MemoryPreferences());
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.build(Brightness.dark),
                home: TerminalScreen(settings: settings),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(commands, ['STATUS']);
          await capture(tester, 'terminal-${size.width.toInt()}');
          await tester.enterText(find.byType(TextField), 'help');
          await tester.tap(find.byTooltip('Send command'));
          await tester.pumpAndSettle();
          expect(commands.last, 'HELP');
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          await tester.enterText(find.byType(TextField), 'PAIR');
          await tester.tap(find.byTooltip('Send command'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Show pairing QR'));
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsOneWidget);
          await capture(tester, 'terminal-qr-${size.width.toInt()}');
          final countBeforePause = commands.length;
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pump(const Duration(seconds: 10));
          await tester.pumpAndSettle();
          expect(find.byType(QrImageView), findsNothing);
          expect(find.byType(Dialog), findsNothing);
          expect(commands.length, countBeforePause);
          expect(
            tester
                .widget<SelectableText>(find.byType(SelectableText).first)
                .data,
            isNot(contains('34970112332')),
          );
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await tester.pumpAndSettle();
          expect(commands.last, '');
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
          return reply(request.body);
        }),
      );
    });
  }

  testWidgets('reading older logs stays stable when live history rolls over', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var cursor = 0;
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
        final logScroll = find.byType(SingleChildScrollView).last;
        await tester.drag(logScroll, const Offset(0, 350));
        await tester.pumpAndSettle();
        expect(find.text('Resume live logs'), findsOneWidget);
        final before = tester
            .widget<SelectableText>(find.byType(SelectableText).first)
            .data;
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText).first).data,
          before,
        );
        await tester.tap(find.text('Resume live logs'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText).first).data,
          contains('Log $cursor'),
        );
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
        final first = cursor == 0;
        cursor = first ? 300 : cursor + 1;
        return http.Response(
          jsonEncode({
            'version': 1,
            'boot': 'abc',
            'cursor': cursor,
            'gap': false,
            'lines': [
              for (var i = first ? 1 : cursor; i <= cursor; i++)
                {'id': i, 'text': 'Log $i'},
            ],
            'output': '',
            'ok': true,
            'commissioned': false,
            'pairing_code': null,
          }),
          200,
        );
      }),
    );
  });

  for (final home in HomeEcosystem.values) {
    testWidgets(
      '${home.label} gets a real code and switches to sharing after pairing',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var paired = false;
        final commands = <String>[];
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.build(Brightness.light),
                  home: HomeSetupScreen(
                    settings: DeviceSettings(preferences: MemoryPreferences()),
                    ecosystem: home,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Get setup code'));
            await tester.pumpAndSettle();
            expect(commands, ['STATUS', 'STATUS', 'PAIR']);
            expect(find.text('34970112332'), findsOneWidget);
            expect(find.byType(QrImageView), findsOneWidget);
            expect(find.text('Get setup code'), findsNothing);
            expect(find.byTooltip('Pairing options'), findsOneWidget);
            await capture(tester, 'setup-${home.name}');
            // Pairing on this phone requires leaving LockLink. On return the
            // secret is gone, but the promised next action must still exist.
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
            await tester.pumpAndSettle();
            expect(find.byType(QrImageView), findsNothing);
            expect(find.text('34970112332'), findsNothing);
            expect(find.text('Check pairing'), findsOneWidget);
            await tester.ensureVisible(find.text('Get code again'));
            await tester.tap(find.text('Get code again'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Enlarge QR'));
            await tester.tap(find.text('Enlarge QR'));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsOneWidget);
            // A live status update must revoke an already-open QR view.
            paired = true;
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(find.byType(QrImageView), findsNothing);
            expect(find.text('Already paired'), findsOneWidget);
            expect(find.text('Copy code'), findsNothing);
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
            return reply(request.body, paired: paired);
          }),
        );
      },
    );
  }

  testWidgets('backgrounding cancels the guide STATUS to PAIR sequence', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var statusCount = 0;
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
        await tester.tap(find.text('Get setup code'));
        await tester.pump();
        expect(statusCount, 2);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        pending.complete(reply('STATUS'));
        await tester.pumpAndSettle();
        expect(commands, isNot(contains('PAIR')));
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Get setup code'), findsOneWidget);
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
        if (request.body == 'STATUS' && ++statusCount == 2) {
          return pending.future;
        }
        return reply(request.body);
      }),
    );
  });

  testWidgets('terminal fits large text with the keyboard open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 440));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: TerminalScreen(
            settings: DeviceSettings(preferences: MemoryPreferences()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
