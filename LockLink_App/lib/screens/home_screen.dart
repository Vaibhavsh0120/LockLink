import 'dart:async';

import 'package:flutter/material.dart';

import '../models/door_status.dart';
import '../services/app_haptics.dart';
import '../services/device_settings.dart';
import '../services/locklink_api_service.dart';
import '../widgets/door_control_card.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.themeMode,
  });

  final DeviceSettings settings;
  final ValueNotifier<ThemeMode> themeMode;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DeviceSettings get _settings => widget.settings;
  final AppHaptics _haptics = AppHaptics();
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
    var hapticsEnabled = false;
    try {
      hapticsEnabled = await _settings.loadHapticsEnabled();
    } catch (_) {
      // An optional feedback preference must not prevent device control.
    }
    if (!mounted) return;
    _haptics.enabled = hapticsEnabled;
    final address = await _settings.loadAddress();
    if (!mounted) return;
    _connect(address);
    _unlockKey = await _settings.loadUnlockKey(address);
    if (!mounted) return;
    setState(() => _loading = false);
    await _refresh();
  }

  void _connect(String? address) {
    _api?.close();
    _address = address;
    _api = address == null ? null : LockLinkApiService(address);
    _checking = false;
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

  Future<void> _refresh({bool userInitiated = false}) async {
    final api = _api;
    if (api == null || _checking || _unlocking) return;
    _checking = true;
    if (userInitiated) _haptics.tap();
    try {
      final DoorStatus status = await api.getStatus();
      if (!mounted || api != _api) return;
      setState(() {
        _online = status.online;
        _deviceState = status.state;
        _relayMode = status.mode == 'relay';
        _armed = status.armed;
      });
      if (userInitiated && !status.online) _haptics.error();
    } catch (_) {
      if (!mounted || api != _api) return;
      setState(() => _online = false);
      if (userInitiated) _haptics.error();
    } finally {
      if (api == _api) _checking = false;
    }
  }

  Future<void> _unlock() async {
    final api = _api;
    if (api == null || !_online || _unlocking || _deviceState == 'unlocking') {
      return;
    }
    setState(() => _unlocking = true);
    _haptics.tap();
    try {
      final duration = await api.unlockDoor(
        relayMode: _relayMode,
        unlockKeyHex: _unlockKey,
      );
      if (!mounted || api != _api) return;
      setState(() => _pairingError = false);
      // The device accepted the command; this is not a door-sensor reading.
      _haptics.success();
      await Future<void>.delayed(duration);
    } on DeviceException catch (error) {
      if (mounted && api == _api) {
        _haptics.error();
        _showMessage(
          error.statusCode == 401
              ? 'Pairing key rejected. Update it in device settings.'
              : error.statusCode == 409
              ? 'The device is already unlocking. Try again shortly.'
              : 'Could not unlock. Check your device and try again.',
        );
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
        _haptics.error();
        _showMessage('Could not unlock. Check your device and try again.');
        setState(() => _online = false);
      }
    } finally {
      if (mounted && api == _api) {
        setState(() => _unlocking = false);
        await _refresh();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editAddress() async {
    _haptics.tap();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          settings: _settings,
          haptics: _haptics,
          themeMode: widget.themeMode,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    try {
      final address = await _settings.loadAddress();
      final savedKey = await _settings.loadUnlockKey(address);
      if (!mounted) return;
      setState(() {
        _connect(address);
        _unlockKey = savedKey;
      });
      await _refresh();
    } catch (_) {
      if (mounted) {
        _showMessage('Could not load device settings. Please try again.');
      }
    }
  }

  @override
  void dispose() {
    _haptics.enabled = false;
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
                              onPressed: _address == null || _loading
                                  ? null
                                  : () => _refresh(userInitiated: true),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                            IconButton(
                              tooltip: 'Device settings',
                              onPressed: _loading ? null : _editAddress,
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
