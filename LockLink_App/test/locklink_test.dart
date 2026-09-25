import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/services/device_settings.dart';
import 'package:locklink/services/locklink_api_service.dart';

void main() {
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
