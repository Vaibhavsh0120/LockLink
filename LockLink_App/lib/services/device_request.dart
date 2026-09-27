import 'dart:async';

import 'package:http/http.dart' as http;

/// A timeout also aborts transport work; it never queues or retries a command.
Future<http.Response> deviceRequest(
  http.Client client,
  String method,
  Uri url, {
  required Duration timeout,
  Map<String, String>? headers,
  String? body,
}) async {
  final abort = Completer<void>();
  final request = http.AbortableRequest(
    method,
    url,
    abortTrigger: abort.future,
  );
  if (headers != null) request.headers.addAll(headers);
  if (body != null) request.body = body;
  try {
    return await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  } finally {
    // Future.timeout alone leaves the socket request running. Supported by
    // both http's IOClient and BrowserClient, including response body reads.
    // Cancellation cannot undo a command already accepted by the ESP32.
    abort.complete();
  }
}
