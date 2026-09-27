import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locklink/services/terminal_service.dart';

void main() {
  test(
    'Matter QR is optional and malformed data preserves the manual code',
    () {
      const payload = 'MT:Y.K9042C00KA0648G00';
      for (final qr in [
        payload,
        null,
        42,
        '',
        'https://example.com',
        'MT:bad',
        'MT:ZZZZZZZZZZZZZZZZZZZ',
      ]) {
        final reply = TerminalReply.fromJson({
          'version': 1,
          'boot': 'abc',
          'cursor': 1,
          'gap': false,
          'lines': [],
          'output': '',
          'ok': true,
          'commissioned': false,
          'pairing_code': '34970112332',
          'pairing_qr_payload': qr,
        });
        expect(reply.pairingCode, '34970112332');
        expect(reply.pairingQrPayload, qr == payload ? payload : null);
      }
      for (final state in [
        {'ok': false, 'commissioned': false},
        {'ok': true, 'commissioned': true},
      ]) {
        final reply = TerminalReply.fromJson({
          'version': 1,
          'boot': 'abc',
          'cursor': 1,
          'gap': false,
          'lines': [],
          'output': '',
          ...state,
          'pairing_code': '34970112332',
          'pairing_qr_payload': payload,
        });
        expect(reply.pairingQrPayload, isNull);
        expect(reply.pairingCode, isNull);
      }
    },
  );
  test('rejects invalid firmware cursors before they enter session state', () {
    for (final invalid in [
      {'boot': 'not/hex', 'cursor': 1},
      {'boot': 'abc', 'cursor': 0x100000000},
    ]) {
      expect(
        () => TerminalReply.fromJson({
          'version': 1,
          ...invalid,
          'gap': false,
          'lines': [],
          'output': '',
          'ok': true,
          'commissioned': false,
          'pairing_code': null,
        }),
        throwsFormatException,
      );
    }
  });
  const key =
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
  const nonce = '00112233445566778899aabbccddeeff';

  test(
    'terminal signs command and cursor without using unlock challenge',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/terminal/challenge') {
          return http.Response(jsonEncode({'nonce': nonce}), 200);
        }
        expect(request.url.path, '/terminal');
        expect(request.method, 'POST');
        expect(request.body, 'PAIR');
        expect(request.url.queryParameters, {'after': '9', 'boot': 'abc'});
        final bytes = List.generate(32, (i) => i);
        expect(
          request.headers['X-LockLink-Signature'],
          Hmac(
            sha256,
            bytes,
          ).convert(utf8.encode('terminal:9:abc:PAIR:$nonce')).toString(),
        );
        return http.Response(
          jsonEncode({
            'version': 1,
            'boot': 'abc',
            'cursor': 10,
            'gap': false,
            'lines': [
              {'id': 10, 'text': 'Wi-Fi connected.'},
            ],
            'output': 'Code: 34970112332',
            'ok': true,
            'commissioned': false,
            'pairing_code': '34970112332',
          }),
          200,
        );
      });
      final service = TerminalService(
        'http://192.168.0.111',
        key,
        client: client,
      );
      final reply = await service.exchange(
        command: ' pair ',
        after: 9,
        boot: 'abc',
      );
      expect(reply.pairingCode, '34970112332');
      expect(reply.lines.single, 'Wi-Fi connected.');
      expect(reply.cursor, 10);
      service.close();
    },
  );

  test('old firmware and rejected keys have actionable errors', () async {
    for (final status in [404, 401, 503]) {
      final service = TerminalService(
        'http://192.168.0.111',
        key,
        client: MockClient((_) async => http.Response('{}', status)),
      );
      await expectLater(service.exchange(), throwsA(isA<TerminalException>()));
      service.close();
    }
  });

  test('rejects multiline commands before sending any request', () async {
    final service = TerminalService(
      'http://192.168.0.111',
      key,
      client: MockClient((_) async => fail('Must not send invalid commands')),
    );
    await expectLater(
      service.exchange(command: 'STATUS\nPAIR'),
      throwsFormatException,
    );
    service.close();
  });
}
