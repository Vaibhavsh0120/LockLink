import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/device_request.dart';
import 'package:locklink/services/locklink_api_service.dart';
import 'package:locklink/services/terminal_service.dart';

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

class RedirectProbeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.followRedirects, isFalse);
    return http.StreamedResponse(const Stream.empty(), 302);
  }
}

void main() {
  test('local requests reject redirects and unsafe stored addresses', () async {
    for (final address in [
      'http://user@192.168.1.50',
      'http://192.168.1.50/unlock',
      'http://192.168.1.50?x=1',
    ]) {
      expect(() => LockLinkApiService(address), throwsFormatException);
      expect(
        () => TerminalService(address, DeviceSettings.defaultPairingKey),
        throwsFormatException,
      );
    }
    final client = RedirectProbeClient();
    for (final method in ['GET', 'POST']) {
      expect(
        (await deviceRequest(
          client,
          method,
          Uri.parse('http://192.168.1.50/status'),
          timeout: const Duration(seconds: 1),
        )).statusCode,
        302,
      );
    }
    await expectLater(
      deviceRequest(
        client,
        'GET',
        Uri.parse('http://0172.16.0.1/status'),
        timeout: const Duration(seconds: 1),
      ),
      throwsFormatException,
    );
  });
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
    for (final address in [
      'http://0172.16.0.1',
      'http://192.168.01.50',
      'http://10.1.2.3:0',
      'http://10.1.2.3:65536',
    ]) {
      expect(DeviceSettings.normalizeAddress(address), isNull);
    }
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

  test('relay status must explicitly report an armed output', () async {
    final api = LockLinkApiService(
      'http://192.168.1.50',
      client: MockClient(
        (_) async => http.Response(
          '{"online":true,"state":"locked","mode":"relay"}',
          200,
        ),
      ),
    );
    expect((await api.getStatus()).armed, isFalse);
    api.close();
  });

  test('rejects malformed or unconfirmed unlock responses', () async {
    for (final response in [
      http.Response('{"success":true}', 200),
      http.Response('{}', 500),
      http.Response('{}', 503),
      http.Response(
        '{"success":true,"state":"unlocking","duration_ms":0}',
        200,
      ),
    ]) {
      final api = LockLinkApiService(
        'http://192.168.1.50',
        client: MockClient((_) async => response),
      );
      await expectLater(api.unlockDoor(), throwsFormatException);
      api.close();
    }
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
