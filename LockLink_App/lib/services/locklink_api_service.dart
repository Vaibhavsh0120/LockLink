import 'dart:convert';

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

  Future<Duration> unlockDoor() async {
    final response = await _client
        .post(Uri.parse('$baseUrl/unlock'))
        .timeout(timeout);
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
