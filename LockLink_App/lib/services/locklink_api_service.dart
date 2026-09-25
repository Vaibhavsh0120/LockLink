import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/door_status.dart';

class LockLinkApiService {
  LockLinkApiService(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  static const timeout = Duration(seconds: 4);

  Future<DoorStatus> getStatus() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/status'))
        .timeout(timeout);
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
      final challengeResponse = await _client
          .get(Uri.parse('$baseUrl/challenge'))
          .timeout(timeout);
      if (challengeResponse.statusCode != 200) {
        throw DeviceException(
          'Challenge failed',
          statusCode: challengeResponse.statusCode,
        );
      }
      final challenge = jsonDecode(challengeResponse.body);
      if (challenge is! Map<String, dynamic> ||
          challenge['nonce'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(challenge['nonce'] as String)) {
        throw const FormatException('Unexpected challenge response');
      }
      final nonce = challenge['nonce'] as String;
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
    final response = await _client
        .post(Uri.parse('$baseUrl/unlock'), headers: headers)
        .timeout(timeout);
    if (response.statusCode == 401) {
      throw const DeviceException('Pairing key rejected', statusCode: 401);
    }
    if (response.statusCode == 409) {
      throw const DeviceException('Door is already unlocking', statusCode: 409);
    }
    if (response.statusCode != 200) {
      throw DeviceException('Device returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['success'] != true ||
        body['state'] != 'unlocking' ||
        body['duration_ms'] is! int) {
      throw const FormatException('Unexpected unlock response');
    }
    return Duration(milliseconds: body['duration_ms'] as int);
  }

  void close() => _client.close();
}

class DeviceException implements Exception {
  const DeviceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
