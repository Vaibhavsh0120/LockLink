import 'dart:async';

import 'package:flutter/material.dart';

import '../models/door_status.dart';
import '../services/device_settings.dart';
import '../services/locklink_api_service.dart';
import '../widgets/door_control_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DeviceSettings _settings = DeviceSettings();
  LockLinkApiService? _api;
  Timer? _pollTimer;
  String? _address;
  bool _loading = true;
  bool _checking = false;
  bool _online = false;
  bool _unlocking = false;
  bool _relayMode = false;
  bool _armed = true;
  bool _pairingError = false;
  String? _unlockKey;
  String _deviceState = 'locked';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final address = await _settings.loadAddress();
    if (!mounted) return;
    _connect(address);
    if (address != null) {
      _unlockKey = await _settings.loadUnlockKey(address);
      if (!mounted) return;
    }
    setState(() => _loading = false);
    if (address != null) await _refresh();
  }

  void _connect(String? address) {
    _api?.close();
    _address = address;
    _api = address == null ? null : LockLinkApiService(address);
    _online = false;
    _relayMode = false;
    _armed = true;
    _pairingError = false;
    _unlockKey = null;
    _deviceState = 'locked';
    _pollTimer?.cancel();
    if (address != null) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _refresh(),
      );
    }
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null || _checking || _unlocking) return;
    _checking = true;
    try {
      final DoorStatus status = await api.getStatus();
      if (!mounted || api != _api) return;
      setState(() {
        _online = status.online;
        _deviceState = status.state;
        _relayMode = status.mode == 'relay';
        _armed = status.armed;
      });
    } catch (_) {
      if (!mounted || api != _api) return;
      setState(() => _online = false);
    } finally {
      _checking = false;
    }
  }

  Future<void> _unlock() async {
    final api = _api;
    if (api == null || !_online || _unlocking || _deviceState == 'unlocking') {
      return;
    }
    setState(() => _unlocking = true);
    try {
      final duration = await api.unlockDoor(
        relayMode: _relayMode,
        unlockKeyHex: _unlockKey,
      );
      if (!mounted || api != _api) return;
      setState(() => _pairingError = false);
      await Future<void>.delayed(duration);
    } on DeviceException catch (error) {
      if (mounted && api == _api) {
        if (error.statusCode == 401) {
          setState(() => _pairingError = true);
        } else if (error.statusCode == 503) {
          setState(() => _armed = false);
        } else if (error.statusCode != 409) {
          setState(() => _online = false);
        }
      }
    } catch (_) {
      if (mounted && api == _api) {
        setState(() => _online = false);
      }
    } finally {
      if (mounted && api == _api) {
        setState(() => _unlocking = false);
        await _refresh();
      }
    }
  }

  Future<void> _editAddress() async {
    final controller = TextEditingController(
      text: _address ?? 'http://192.168.1.',
    );
    final keyController = TextEditingController();
    String? error;
    String? keyError;
    void submit(BuildContext dialogContext, StateSetter update) {
      final address = DeviceSettings.normalizeAddress(controller.text);
      final key = keyController.text.trim();
      update(() {
        error = address == null ? 'Use a local http:// address' : null;
        keyError = key.isNotEmpty && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)
            ? 'Use a 64-character hex key'
            : null;
      });
      if (address != null && keyError == null) {
        Navigator.pop(dialogContext, (address: address, key: key));
      }
    }

    final result = await showDialog<({String address, String key})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connect your device'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the ESP32 address shown in its serial monitor. Your phone and device must share the same Wi-Fi.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Device address',
                  hintText: 'http://192.168.1.50',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(dialogContext, update),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Pairing key for relay',
                  hintText: 'Leave blank to keep saved key',
                  errorText: keyError,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => submit(dialogContext, update),
              child: const Text('Save address'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    keyController.dispose();
    if (result == null || !mounted) return;
    await _settings.saveAddress(result.address);
    if (result.key.isNotEmpty) {
      await _settings.saveUnlockKey(result.address, result.key);
    }
    final savedKey = await _settings.loadUnlockKey(result.address);
    if (!mounted) return;
    setState(() {
      _connect(result.address);
      _unlockKey = savedKey;
    });
    await _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = _online && (_unlocking || _deviceState == 'unlocking');
    final ready =
        !_relayMode || (_armed && _unlockKey != null && !_pairingError);
    final stateLabel = _address == null
        ? 'Not connected'
        : !_online
        ? 'Offline'
        : _relayMode && !_armed
        ? 'Not armed'
        : _relayMode && !ready
        ? 'Pair device'
        : active
        ? 'Unlocking…'
        : _relayMode
        ? 'Ready'
        : 'Locked';
    final statusText = _address == null
        ? 'Not connected'
        : !_online
        ? 'Offline'
        : !ready
        ? 'Setup needed'
        : 'Online';
    final helperText = _address == null
        ? 'Add device address'
        : !_online
        ? 'Check Wi-Fi and device'
        : _relayMode && !_armed
        ? 'Set key in ESP32'
        : _pairingError
        ? 'Pairing key rejected'
        : _relayMode && _unlockKey == null
        ? 'Add key in settings'
        : null;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final horizontalPadding = compact ? 20.0 : 32.0;
            final topPadding = compact ? 20.0 : 32.0;
            const bottomPadding = 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                bottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight - topPadding - bottomPadding,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.lock_outline_rounded,
                                color: colors.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'LockLink',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Check connection',
                              onPressed: _address == null ? null : _refresh,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                            IconButton(
                              tooltip: 'Device settings',
                              onPressed: _editAddress,
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Front Door',
                              style:
                                  (compact
                                          ? theme.textTheme.headlineMedium
                                          : theme.textTheme.headlineLarge)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -1.1,
                                      ),
                            ),
                            const SizedBox(height: 24),
                            DoorControlCard(
                              online: _online,
                              ready: ready,
                              active: active,
                              stateLabel: stateLabel,
                              statusText: statusText,
                              helperText: helperText,
                              onUnlock: ready ? _unlock : null,
                              compact: compact,
                            ),
                            if (_loading) ...[
                              const SizedBox(height: 16),
                              const Center(child: CircularProgressIndicator()),
                            ] else if (_address == null) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _editAddress,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Connect device'),
                              ),
                            ],
                          ],
                        ),
                        Center(
                          child: Text(
                            _relayMode
                                ? 'Local only  ·  Lock control'
                                : 'Local only  ·  LED prototype',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
