import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_settings.dart';
import 'terminal_service.dart';

/// One in-flight exchange per screen; never retries a command automatically.
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.settings);
  final DeviceSettings settings;
  TerminalService? _service;
  Timer? _timer;
  bool _disposed = false;
  bool _active = true;
  bool _retry = true;
  bool busy = false;
  bool _polling = false;
  bool _queuedCommand = false;
  Completer<void>? _exchangeDone;
  int _activityEpoch = 0;
  bool get sendingCommand => (busy && !_polling) || _queuedCommand;
  bool connected = false;
  String? error;
  String address = '';
  String _boot = '';
  int _cursor = 0;
  final List<String> lines = [];
  TerminalReply? latest;
  String? pairingCode;
  String? pairingQrPayload;
  int _pairingEpoch = 0;
  bool _additionalPairing = false;
  String _pairingHomes = '';
  String? _pairingWindowId;
  DateTime? _pairingDeadline;

  String _homeIds(TerminalReply reply) =>
      ((reply.homes ?? []).map((home) => home.id).toList()..sort()).join(',');

  void _hideCode() {
    _pairingEpoch++;
    pairingCode = null;
    pairingQrPayload = null;
    _additionalPairing = false;
    _pairingHomes = '';
    _pairingWindowId = null;
    _pairingDeadline = null;
    latest = latest?.withoutPairingSecrets();
    for (var i = 0; i < lines.length; i++) {
      lines[i] = lines[i].replaceAll(
        RegExp(r'Code: \d{11,21}'),
        'Code: hidden. Run PAIR to view.',
      );
    }
  }

  Future<void> start() async {
    try {
      address = await settings.loadAddress();
      final key = await settings.loadUnlockKey(address);
      if (_disposed) return;
      _service = TerminalService(address, key);
      await send('STATUS');
    } catch (_) {
      if (!_disposed) {
        error = 'Could not load device settings. Reopen this screen to retry.';
        notifyListeners();
      }
    }
  }

  void setActive(bool value) {
    _activityEpoch++;
    _active = value;
    _timer?.cancel();
    if (!value) {
      connected = false;
      latest = null;
      _hideCode();
      notifyListeners();
    }
    if (value) _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    if (_disposed || !_active || !_retry || _service == null) return;
    _timer = Timer(
      immediate ? Duration.zero : Duration(seconds: connected ? 1 : 5),
      () => send(''),
    );
  }

  Future<TerminalReply?> send(String command) async {
    if (_disposed || !_active || _service == null) return null;
    if (busy) {
      if (command.trim().isEmpty || !_polling || _queuedCommand) return null;
      // Give a deliberate send the next turn after the current read-only poll.
      // Never carry it across a lifecycle change or retry an uncertain command.
      _queuedCommand = true;
      final epoch = _activityEpoch;
      final boot = _boot;
      await _exchangeDone!.future;
      _queuedCommand = false;
      if (_disposed ||
          !_active ||
          !connected ||
          epoch != _activityEpoch ||
          boot != _boot) {
        return null;
      }
      return send(command);
    }
    String normalized;
    try {
      normalized = TerminalService.normalizeCommand(command);
    } on FormatException catch (e) {
      error = e.message;
      notifyListeners();
      return null;
    }
    _timer?.cancel();
    busy = true;
    _polling = normalized.isEmpty;
    _exchangeDone = Completer<void>();
    _retry = true;
    final requestsCode = normalized == 'PAIR' || normalized == 'PAIR ADD';
    if (requestsCode ||
        normalized == 'PAIR CLOSE' ||
        normalized.startsWith('HOME REMOVE ')) {
      _hideCode();
    }
    final pairingEpoch = _pairingEpoch;
    if (normalized.isNotEmpty) lines.add('> $normalized');
    notifyListeners();
    try {
      final reply = await _service!.exchange(
        command: normalized,
        after: _cursor,
        boot: _boot,
      );
      if (_disposed) return null;
      if (_boot.isNotEmpty && _boot != reply.boot) {
        lines.add('Device restarted.');
        _hideCode();
      }
      if (reply.gap) lines.add('Earlier device logs are no longer available.');
      _boot = reply.boot;
      _cursor = reply.cursor;
      final current = _active && pairingEpoch == _pairingEpoch;
      latest = current ? reply.withoutPairingSecrets() : null;
      if (requestsCode) {
        final additional =
            normalized == 'PAIR ADD' && reply.pairingMode == 'additional';
        final canPair =
            current &&
            reply.ok &&
            (!reply.commissioned || (additional && reply.pairingWindowOpen));
        pairingCode = canPair ? reply.pairingCode : null;
        pairingQrPayload = canPair ? reply.pairingQrPayload : null;
        _additionalPairing = canPair && additional && pairingCode != null;
        _pairingHomes = _homeIds(reply);
        _pairingWindowId = reply.pairingWindowId;
        _pairingDeadline = DateTime.now().add(const Duration(minutes: 5));
      }
      lines.addAll(reply.lines);
      if (reply.output.isNotEmpty) lines.addAll(reply.output.split('\n'));
      final addedOrRemoved =
          _additionalPairing &&
          (_homeIds(reply) != _pairingHomes ||
              reply.pairingWindowId != _pairingWindowId);
      final expired =
          _pairingDeadline != null && DateTime.now().isAfter(_pairingDeadline!);
      if (!current ||
          expired ||
          addedOrRemoved ||
          (reply.homes != null &&
              !reply.pairingWindowOpen &&
              pairingCode != null) ||
          (_additionalPairing
              ? !reply.pairingWindowOpen
              : reply.commissioned)) {
        _hideCode();
      }
      connected = current;
      error = null;
      // Obsolete replies must not continue a guide's STATUS → PAIR sequence.
      return current ? reply : null;
    } catch (e) {
      if (_disposed) return null;
      connected = false;
      latest = null;
      _hideCode();
      error = e is TerminalException
          ? e.message
          : 'Unexpected device response. Check the firmware.';
      _retry = e is TerminalException && e.retryable;
      if (normalized.isNotEmpty) {
        lines.add('No confirmed reply. Command was not retried.');
      }
      return null;
    } finally {
      _exchangeDone?.complete();
      _exchangeDone = null;
      if (!_disposed) {
        if (lines.length > 300) lines.removeRange(0, lines.length - 300);
        busy = false;
        _polling = false;
        notifyListeners();
        _schedule();
      }
    }
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _service?.close();
    lines.clear();
    pairingCode = null;
    pairingQrPayload = null;
    latest = null;
    super.dispose();
  }
}
