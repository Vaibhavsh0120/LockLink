import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/locklink_api_service.dart';

class PendingDeviceClient extends http.BaseClient {
  var requests = 0;
  var aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (++requests > 1) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"online":true,"state":"locked"}')),
          200,
        ),
      );
    }
    final pending = Completer<http.StreamedResponse>();
    if (request is http.Abortable) {
      request.abortTrigger!.then((_) {
        aborted = true;
        pending.completeError(http.RequestAbortedException(request.url));
      });
    }
    return pending.future;
  }
}

void main() {
  testWidgets('timed-out device requests abort and the client can reconnect', (
    tester,
  ) async {
    final client = PendingDeviceClient();
    final api = LockLinkApiService('http://192.168.1.50', client: client);
    final failure = expectLater(
      api.unlockDoor(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(LockLinkApiService.timeout);
    await failure;
    expect(client.aborted, isTrue);
    expect((await api.getStatus()).online, isTrue);
    expect(client.requests, 2);
    api.close();
  });
  test('derives the demo signing key while preserving existing hex keys', () {
    expect(
      DeviceSettings.signingKey('1234'),
      '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
    );
    const existingKey =
        '000102030405060708090a0b0c0d0e0f'
        '101112131415161718191a1b1c1d1e1f';
    expect(DeviceSettings.signingKey(existingKey.toUpperCase()), existingKey);
    expect(() => DeviceSettings.signingKey(''), throwsFormatException);
  });

  test('accepts LAN address and rejects public or secure URL', () {
    expect(
      DeviceSettings.normalizeAddress(' http://192.168.1.50/ '),
      'http://192.168.1.50',
    );
    expect(DeviceSettings.normalizeAddress('https://example.com'), isNull);
    expect(DeviceSettings.normalizeAddress('http://example.com'), isNull);
    expect(DeviceSettings.normalizeAddress('http://192.168.1.999'), isNull);
    expect(
      DeviceSettings.normalizeAddress('http://192.168.1.50/unlock'),
      isNull,
    );
  });

  test('reads status and unlock duration from the device API', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/status') {
        return http.Response(
          jsonEncode({'online': true, 'state': 'locked'}),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/unlock') {
        return http.Response(
          jsonEncode({
            'success': true,
            'state': 'unlocking',
            'duration_ms': 2000,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final api = LockLinkApiService('http://192.168.1.50', client: client);
    expect((await api.getStatus()).state, 'locked');
    expect(await api.unlockDoor(), const Duration(seconds: 2));
    api.close();
  });

  test('signs a relay unlock with the one-time challenge', () async {
    const nonce = '00112233445566778899aabbccddeeff';
    const key =
        '000102030405060708090a0b0c0d0e0f'
        '101112131415161718191a1b1c1d1e1f';
    final client = MockClient((request) async {
      if (request.url.path == '/status') {
        return http.Response(
          jsonEncode({
            'online': true,
            'state': 'locked',
            'mode': 'relay',
            'armed': true,
          }),
          200,
        );
      }
      if (request.url.path == '/challenge') {
        return http.Response(jsonEncode({'nonce': nonce}), 200);
      }
      if (request.url.path == '/unlock') {
        expect(request.headers['X-LockLink-Nonce'], nonce);
        expect(
          request.headers['X-LockLink-Signature'],
          '341a767596290df094f966447190fec7ad24056bae49ea7dd64767a5e3774b75',
        );
        return http.Response(
          jsonEncode({
            'success': true,
            'state': 'unlocking',
            'duration_ms': 2000,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final api = LockLinkApiService('http://192.168.1.50', client: client);
    expect((await api.getStatus()).mode, 'relay');
    expect(
      await api.unlockDoor(relayMode: true, unlockKeyHex: key),
      const Duration(seconds: 2),
    );
    api.close();
  });

  test('rejects malformed unlock success', () async {
    final api = LockLinkApiService(
      'http://192.168.1.50',
      client: MockClient((_) async => http.Response('{"success":true}', 200)),
    );
    expect(api.unlockDoor(), throwsFormatException);
    api.close();
  });

  test(
    'reports an already active pulse without treating it as a network error',
    () async {
      final api = LockLinkApiService(
        'http://192.168.1.50',
        client: MockClient((_) async => http.Response('{}', 409)),
      );
      expect(
        api.unlockDoor(),
        throwsA(
          isA<DeviceException>().having((e) => e.statusCode, 'statusCode', 409),
        ),
      );
      api.close();
    },
  );
}
