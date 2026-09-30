import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/matter_pairing_payload.dart';
import '../models/matter_home.dart';
import 'device_request.dart';
import 'device_settings.dart';

class TerminalReply {
  const TerminalReply({
    required this.boot,
    required this.cursor,
    required this.gap,
    required this.lines,
    required this.output,
    required this.ok,
    required this.commissioned,
    this.pairingCode,
    this.pairingQrPayload,
    this.homes,
    this.fabricCapacity,
    this.pairingMode,
    this.pairingWindowId,
    this.pairingWindowOpen = false,
  });

  final String boot;
  final int cursor;
  final bool gap;
  final List<String> lines;
  final String output;
  final bool ok;
  final bool commissioned;
  final String? pairingCode;
  final String? pairingQrPayload;
  final List<MatterHome>? homes;
  final int? fabricCapacity;
  final String? pairingMode;
  final String? pairingWindowId;
  final bool pairingWindowOpen;

  TerminalReply withoutPairingSecrets() => TerminalReply(
    boot: boot,
    cursor: cursor,
    gap: gap,
    lines: lines,
    output: output.replaceAll(
      RegExp(r'Code: \d{11,21}'),
      'Code: hidden. Run PAIR to view.',
    ),
    ok: ok,
    commissioned: commissioned,
    homes: homes,
    fabricCapacity: fabricCapacity,
    pairingMode: pairingMode,
    pairingWindowId: pairingWindowId,
    pairingWindowOpen: pairingWindowOpen,
  );

  factory TerminalReply.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['boot'] is! String ||
        !RegExp(r'^[0-9a-f]{1,16}$').hasMatch(value['boot'] as String) ||
        value['cursor'] is! int ||
        value['cursor'] < 0 ||
        value['cursor'] > 0xffffffff ||
        value['gap'] is! bool ||
        value['lines'] is! List ||
        value['output'] is! String ||
        value['ok'] is! bool ||
        value['commissioned'] is! bool) {
      throw const FormatException('Unexpected terminal response');
    }
    final lines = <String>[];
    for (final line in value['lines'] as List) {
      if (line is! Map || line['text'] is! String || line['id'] is! int) {
        throw const FormatException('Unexpected log entry');
      }
      lines.add(line['text'] as String);
    }
    final code = value['pairing_code'];
    if (code != null &&
        (code is! String || !RegExp(r'^\d{11}$|^\d{21}$').hasMatch(code))) {
      throw const FormatException('Unexpected Matter code');
    }
    List<MatterHome>? homes;
    final capacity = value['fabric_capacity'];
    final windowOpen = value['pairing_window_open'];
    final mode = value['pairing_mode'];
    final windowId = value['pairing_window_id'];
    if (windowId != null &&
        (windowId is! String ||
            !RegExp(r'^[0-9a-f]{16}$').hasMatch(windowId))) {
      throw const FormatException('Unexpected pairing window');
    }
    if (value['homes'] != null) {
      if (value['homes'] is! List ||
          capacity is! int ||
          capacity < 1 ||
          capacity > 254 ||
          windowOpen is! bool ||
          (value['homes'] as List).length > capacity) {
        throw const FormatException('Unexpected home management response');
      }
      homes = List<MatterHome>.unmodifiable(
        (value['homes'] as List).map(MatterHome.fromJson),
      );
      if (homes.map((home) => home.id).toSet().length != homes.length ||
          homes.map((home) => home.index).toSet().length != homes.length ||
          value['commissioned'] != homes.isNotEmpty) {
        throw const FormatException('Inconsistent connected homes');
      }
    }
    final canShowCode =
        value['ok'] == true &&
        (value['commissioned'] == false ||
            (mode == 'additional' &&
                homes != null &&
                windowOpen == true &&
                windowId != null));
    return TerminalReply(
      boot: value['boot'],
      cursor: value['cursor'],
      gap: value['gap'],
      lines: lines,
      output: value['output'],
      ok: value['ok'],
      commissioned: value['commissioned'],
      homes: homes,
      fabricCapacity: homes == null ? null : capacity as int,
      pairingMode: mode is String ? mode : null,
      pairingWindowId: windowId as String?,
      pairingWindowOpen: windowOpen == true,
      pairingCode: canShowCode ? code as String? : null,
      pairingQrPayload: canShowCode && code != null
          ? matterPairingPayload(value['pairing_qr_payload'])
          : null,
    );
  }
}

class TerminalException implements Exception {
  const TerminalException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class TerminalService {
  TerminalService(String address, this.key, {http.Client? client})
    : address =
          DeviceSettings.normalizeAddress(address) ??
          (throw const FormatException('Use a local HTTP device address')),
      _client = client ?? http.Client();
  final String address;
  final String key;
  final http.Client _client;
  static const _timeout = Duration(seconds: 4);

  static String normalizeCommand(String raw) {
    if (raw.contains('\n') || raw.contains('\r')) {
      throw const FormatException('Use one command per line.');
    }
    final value = raw.trim().toUpperCase();
    if (value.length > 128 || !RegExp(r'^[ -~]*$').hasMatch(value)) {
      throw const FormatException('Use up to 128 plain-text characters.');
    }
    return value;
  }

  void _check(http.Response response) {
    switch (response.statusCode) {
      case 200:
        return;
      case 404:
        throw const TerminalException(
          'Update the ESP32 firmware to use Terminal.',
        );
      case 401:
        throw const TerminalException('Pairing key rejected. Check Settings.');
      case 503:
        if (response.body.contains('terminal_key_missing')) {
          throw const TerminalException(
            'Set the app signing key in the ESP32 firmware.',
          );
        }
        throw const TerminalException(
          'Device busy. Try again.',
          retryable: true,
        );
      default:
        throw TerminalException(
          'Device returned ${response.statusCode}. Try again.',
          retryable: true,
        );
    }
  }

  Future<TerminalReply> exchange({
    String command = '',
    int after = 0,
    String boot = '',
  }) async {
    final normalized = normalizeCommand(command);
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
      throw const TerminalException('Check the pairing key in Settings.');
    }
    try {
      final challenge = await deviceRequest(
        _client,
        'GET',
        Uri.parse('$address/terminal/challenge'),
        timeout: _timeout,
      );
      _check(challenge);
      final data = jsonDecode(challenge.body);
      if (data is! Map ||
          data['nonce'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['nonce'] as String)) {
        throw const FormatException('Unexpected terminal challenge');
      }
      final nonce = data['nonce'] as String;
      final bytes = List.generate(
        32,
        (i) => int.parse(key.substring(i * 2, i * 2 + 2), radix: 16),
      );
      final signature = Hmac(sha256, bytes)
          .convert(utf8.encode('terminal:$after:$boot:$normalized:$nonce'))
          .toString();
      final response = await deviceRequest(
        _client,
        'POST',
        Uri.parse('$address/terminal')
            .replace(queryParameters: {'after': '$after', 'boot': boot}),
        headers: {
          'Content-Type': 'text/plain',
          'X-LockLink-Nonce': nonce,
          'X-LockLink-Signature': signature,
        },
        body: normalized,
        timeout: _timeout,
      );
      _check(response);
      return TerminalReply.fromJson(jsonDecode(response.body));
    } on TimeoutException {
      throw const TerminalException(
        'Device did not reply. Check power, Wi-Fi and address.',
        retryable: true,
      );
    } on http.ClientException {
      throw const TerminalException(
        'Cannot reach device. Check power, Wi-Fi and address.',
        retryable: true,
      );
    }
  }

  void close() => _client.close();
}
