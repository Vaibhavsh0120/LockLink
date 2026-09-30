import 'dart:async';

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

http.Response status(bool active) => http.Response(
  '{"online":true,"state":"${active ? 'unlocking' : 'locked'}"}',
  200,
);

class UnavailableSettings extends DeviceSettings {
  UnavailableSettings(this.failAddress)
    : super(preferences: MemoryPreferences());
  final bool failAddress;
  @override
  Future<String> loadAddress() async {
    if (failAddress) throw StateError('Storage unavailable');
    return DeviceSettings.defaultAddress;
  }

  @override
  Future<String> loadUnlockKey(String address) async =>
      throw StateError('Credential unavailable');
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('settings storage failures leave a usable recovery action', (
    tester,
  ) async {
    for (final failAddress in [true, false]) {
      await tester.pumpWidget(
        LockLinkApp(settings: UnavailableSettings(failAddress)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.text(
          'Could not load device settings. Open Settings to try again.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  Future<void> runApp(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
    Future<void> Function() verify,
  ) async {
    const channel = MethodChannel('com.locklink/widgets');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    try {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          LockLinkApp(
            settings: DeviceSettings(preferences: MemoryPreferences()),
          ),
        );
        await tester.pumpAndSettle();
        try {
          await verify();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }, () => MockClient(handler));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    }
  }

  bool active(WidgetTester tester) =>
      tester.widget<DoorControlCard>(find.byType(DoorControlCard)).active;

  testWidgets('offline recovers without replaying an unconfirmed unlock', (
    tester,
  ) async {
    var reachable = false;
    var commands = 0;
    await runApp(
      tester,
      (request) async {
        if (request.method == 'POST') {
          commands++;
          reachable = false;
          throw TimeoutException('reply lost');
        }
        if (!reachable) throw http.ClientException('unreachable');
        return status(false);
      },
      () async {
        expect(find.text('Offline'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        reachable = true;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull,
        );
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(
          find.text('No confirmation. Check the device before retrying.'),
          findsOneWidget,
        );
        expect(find.text('Offline'), findsOneWidget);
        reachable = true;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(commands, 1);
        expect(
          tester.widget<DoorControlCard>(find.byType(DoorControlCard)).online,
          isTrue,
        );
      },
    );
  });

  testWidgets('resume disables control until a fresh status reply arrives', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var reads = 0;
    await runApp(
      tester,
      (_) async {
        if (++reads == 1) return status(false);
        return pending.future;
      },
      () async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          tester.widget<DoorControlCard>(find.byType(DoorControlCard)).online,
          isFalse,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        pending.complete(status(false));
        await tester.pumpAndSettle();
        expect(
          tester.widget<DoorControlCard>(find.byType(DoorControlCard)).online,
          isTrue,
        );
      },
    );
  });

  testWidgets('external release and early Off follow device within one poll', (
    tester,
  ) async {
    var released = false;
    await runApp(tester, (_) async => status(released), () async {
      expect(active(tester), isFalse);
      released = true;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(active(tester), isTrue);
      released = false;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(active(tester), isFalse);
    });
  });

  testWidgets('local release follows early Off without a fixed UI timer', (
    tester,
  ) async {
    var released = false;
    var commands = 0;
    await runApp(
      tester,
      (request) async {
        if (request.method == 'POST') {
          commands++;
          released = true;
          return http.Response(
            '{"success":true,"state":"unlocking","duration_ms":1000}',
            200,
          );
        }
        return status(released);
      },
      () async {
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(active(tester), isTrue);
        released = false;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(active(tester), isFalse);
        expect(commands, 1);
      },
    );
  });

  testWidgets('an older status response cannot undo a newer release command', (
    tester,
  ) async {
    var reads = 0;
    final oldRead = Completer<http.Response>();
    final freshRead = Completer<http.Response>();
    await runApp(
      tester,
      (request) async {
        if (request.method == 'POST') {
          return http.Response(
            '{"success":true,"state":"unlocking","duration_ms":1000}',
            200,
          );
        }
        reads++;
        if (reads == 2) return oldRead.future;
        if (reads == 3) return freshRead.future;
        return status(false);
      },
      () async {
        await tester.pump(const Duration(milliseconds: 500));
        expect(reads, 2);
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(active(tester), isTrue);
        oldRead.complete(status(false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(reads, 3);
        expect(active(tester), isTrue);
        freshRead.complete(status(false));
        await tester.pump();
        await tester.pump();
        expect(active(tester), isFalse);
      },
    );
  });

  testWidgets(
    'background pauses reads; resume discards stale response and refreshes',
    (tester) async {
      var reads = 0;
      final delayed = Completer<http.Response>();
      await runApp(
        tester,
        (_) async {
          reads++;
          if (reads == 2) return delayed.future;
          return status(reads > 2);
        },
        () async {
          await tester.pump(const Duration(milliseconds: 500));
          expect(reads, 2);
          await tester.pump(const Duration(seconds: 1));
          expect(reads, 2); // No overlapping status requests.
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          delayed.complete(status(false));
          await tester.pump();
          await tester.pump(const Duration(seconds: 10));
          expect(reads, 2);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.pump();
          expect(reads, 3);
          expect(active(tester), isTrue);
        },
      );
    },
  );
}
