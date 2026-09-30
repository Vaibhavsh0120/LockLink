import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/door_status.dart';
import 'device_request.dart';
import 'device_settings.dart';

class LockLinkApiService {
  LockLinkApiService(
    String baseUrl, {
    http.Client? client,
    Duration Function()? elapsed,
  }) : baseUrl =
           DeviceSettings.normalizeAddress(baseUrl) ??
           (throw const FormatException('Use a local HTTP device address')),
       _client = client ?? http.Client(),
       _elapsed = elapsed ?? _monotonicNow;

  final String baseUrl;
  final http.Client _client;
  final Duration Function() _elapsed;
  static final _clock = Stopwatch()..start();
  static Duration _monotonicNow() => _clock.elapsed;
  _UnlockChallenge? _preparedChallenge;
  Future<void>? _preparingUnlock;
  int _challengeGeneration = 0;
  bool _closed = false;
  static const timeout = Duration(seconds: 4);

  /// Preparation cannot release the relay. Keep at most one cached nonce,
  /// shared by concurrent callers, and avoid renewing an unused server slot
  /// until its ten-second lifetime ends.
  Future<void> prepareUnlock() {
    if (_closed) return Future.value();
    final pending = _preparingUnlock;
    if (pending != null) return pending;
    final prepared = _preparedChallenge;
    if (prepared != null &&
        _elapsed() - prepared.requestedAt <= const Duration(seconds: 10)) {
      return Future.value();
    }
    final generation = _challengeGeneration;
    late final Future<void> preparation;
    preparation = _fetchChallenge()
        .then((challenge) {
          if (!_closed && generation == _challengeGeneration) {
            _preparedChallenge = challenge;
          }
        })
        .whenComplete(() {
          if (identical(_preparingUnlock, preparation)) _preparingUnlock = null;
        });
    _preparingUnlock = preparation;
    return preparation;
  }

  void discardPreparedUnlock() {
    _challengeGeneration++;
    _preparedChallenge = null;
  }

  Future<_UnlockChallenge> _fetchChallenge() async {
    final requestedAt = _elapsed();
    final response = await deviceRequest(
      _client,
      'GET',
      Uri.parse('$baseUrl/challenge'),
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw DeviceException(
        'Challenge failed',
        statusCode: response.statusCode,
      );
    }
    final challenge = jsonDecode(response.body);
    if (challenge is! Map<String, dynamic> ||
        challenge['nonce'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(challenge['nonce'] as String)) {
      throw const FormatException('Unexpected challenge response');
    }
    return _UnlockChallenge(challenge['nonce'] as String, requestedAt);
  }

  Future<DoorStatus> getStatus() async {
    final response = await deviceRequest(
      _client,
      'GET',
      Uri.parse('$baseUrl/status'),
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw DeviceException('Device returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Unexpected device response');
    }
    return DoorStatus.fromJson(body);
  }

  Future<Duration> unlockDoor({
    bool relayMode = false,
    String? unlockKeyHex,
  }) async {
    final headers = <String, String>{};
    if (relayMode) {
      if (unlockKeyHex == null ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(unlockKeyHex)) {
        throw const DeviceException('Pairing key required');
      }
      final preparing = _preparingUnlock;
      if (preparing != null) {
        try {
          await preparing;
        } catch (_) {
          // Preparation is optional. Fetch a fresh challenge below; no unlock
          // request has been sent, and the release POST is never retried.
        }
      }
      final prepared = _preparedChallenge;
      discardPreparedUnlock(); // Never reuse a nonce, even after a failed POST.
      // Allow five seconds of age from request START, leaving the four-second
      // POST timeout within the firmware's ten-second nonce lifetime.
      final challenge =
          prepared != null &&
              _elapsed() - prepared.requestedAt < const Duration(seconds: 5)
          ? prepared
          : await _fetchChallenge();
      final nonce = challenge.nonce;
      final keyBytes = List<int>.generate(
        32,
        (i) => int.parse(unlockKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
      );
      final signature = Hmac(
        sha256,
        keyBytes,
      ).convert(utf8.encode('unlock:$nonce')).toString();
      headers['X-LockLink-Nonce'] = nonce;
      headers['X-LockLink-Signature'] = signature;
    }
    final response = await deviceRequest(
      _client,
      'POST',
      Uri.parse('$baseUrl/unlock'),
      headers: headers,
      timeout: timeout,
    );
    if (response.statusCode == 401) {
      throw const DeviceException('Pairing key rejected', statusCode: 401);
    }
    if (response.statusCode == 409) {
      throw const DeviceException('Door is already unlocking', statusCode: 409);
    }
    if (response.statusCode != 200) {
      throw const FormatException('No confirmed unlock response');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['success'] != true ||
        body['state'] != 'unlocking' ||
        body['duration_ms'] is! int ||
        (body['duration_ms'] as int) <= 0) {
      throw const FormatException('Unexpected unlock response');
    }
    return Duration(milliseconds: body['duration_ms'] as int);
  }

  void close() {
    _closed = true;
    discardPreparedUnlock();
    _client.close();
  }
}

class _UnlockChallenge {
  const _UnlockChallenge(this.nonce, this.requestedAt);
  final String nonce;
  final Duration requestedAt;
}

class DeviceException implements Exception {
  const DeviceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
