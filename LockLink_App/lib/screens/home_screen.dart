import 'dart:async';

import 'package:flutter/material.dart';

import '../models/door_status.dart';
import '../services/app_haptics.dart';
import '../services/device_settings.dart';
import '../services/locklink_api_service.dart';
import '../services/widget_bridge.dart';
import '../widgets/door_control_card.dart';
import '../widgets/device_connection_help.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DeviceSettings get _settings => widget.settings;
  final AppHaptics _haptics = AppHaptics();
  LockLinkApiService? _api;
  Timer? _pollTimer;
  String? _address;
  bool _loading = true;
  bool _checking = false;
  bool _userChecking = false;
  bool _foreground = true;
  bool _settingsOpen = false;
  int _statusGeneration = 0;
  bool _online = false;
  bool _hasChecked = false;
  bool _hasConnected = false;
  int _connectionFailures = 0;
  String? _connectionIssue;
  bool _unlocking = false;
  bool _relayMode = false;
  bool _armed = true;
  bool _pairingError = false;
  bool _settingsError = false;
  String? _unlockKey;
  String _deviceState = 'locked';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _api?.discardPreparedUnlock();
    _statusGeneration++;
    _pollTimer?.cancel();
    setState(() {
      _online = false;
      _hasChecked = _settingsError;
      _connectionFailures = 0;
      _connectionIssue = null;
    });
    if (_foreground && !_loading) unawaited(_refresh());
  }

  void _scheduleRefresh({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!mounted ||
        !_foreground ||
        _settingsOpen ||
        _api == null ||
        _unlocking) {
      return;
    }
    _pollTimer = Timer(
      immediate
          ? Duration.zero
          : _online
          ? const Duration(milliseconds: 500)
          : _connectionFailures <= 1
          ? const Duration(seconds: 1)
          : _connectionFailures == 2
          ? const Duration(seconds: 2)
          : const Duration(seconds: 5),
      () => unawaited(_refresh()),
    );
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
    try {
      final address = await _settings.loadAddress();
      final key = await _loadOptionalKey(address);
      if (!mounted) return;
      _connect(address);
      _unlockKey = key;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connect(null);
        _settingsError = true;
        _hasChecked = true;
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    unawaited(
      WidgetBridge.synchronize(_settings).catchError((Object _) {
        // Settings offers an explicit retry without blocking gate control.
      }),
    );
    await _refresh();
  }

  Future<String?> _loadOptionalKey(String address) async {
    try {
      return await _settings.loadUnlockKey(address);
    } on MissingPairingKeyException {
      return null;
    }
  }

  void _connect(String? address) {
    _api?.close();
    _address = address;
    _api = address == null ? null : LockLinkApiService(address);
    _statusGeneration++;
    _checking = false;
    _userChecking = false;
    _unlocking = false;
    _online = false;
    _hasChecked = false;
    _hasConnected = false;
    _connectionFailures = 0;
    _connectionIssue = null;
    _relayMode = false;
    _armed = true;
    _pairingError = false;
    _settingsError = false;
    _unlockKey = null;
    _deviceState = 'locked';
    _pollTimer?.cancel();
  }

  Future<void> _refresh({bool userInitiated = false}) async {
    final api = _api;
    if (api == null || !_foreground || _settingsOpen || _unlocking) return;
    if (_checking) return;
    _pollTimer?.cancel();
    final generation = _statusGeneration;
    setState(() {
      _checking = true;
      _userChecking = userInitiated;
    });
    if (userInitiated) {
      _haptics.tap();
    }
    try {
      final DoorStatus status = await api.getStatus();
      if (!mounted || api != _api || generation != _statusGeneration) return;
      setState(() {
        _hasChecked = true;
        _online = status.online;
        _hasConnected = _hasConnected || status.online;
        _connectionFailures = status.online ? 0 : 3;
        _connectionIssue = null;
        _deviceState = status.state;
        _relayMode = status.mode == 'relay';
        _armed = status.armed;
      });
      if (status.online &&
          status.state == 'locked' &&
          status.mode == 'relay' &&
          status.armed &&
          _unlockKey != null &&
          !_pairingError) {
        unawaited(
          api.prepareUnlock().catchError((Object _) {
            // Optional preparation never changes readiness or sends a release.
          }),
        );
      } else {
        api.discardPreparedUnlock();
      }
      if (userInitiated && !status.online) _haptics.error();
    } catch (error) {
      if (!mounted || api != _api || generation != _statusGeneration) return;
      api.discardPreparedUnlock();
      setState(() {
        _online = false;
        _hasChecked = true;
        // Brief transport failures get two quick read-only recovery checks.
        // Invalid responses need address/firmware attention, not rapid retries.
        _connectionFailures =
            error is FormatException || error is DeviceException
            ? 3
            : _connectionFailures + 1;
        _connectionIssue = error is FormatException || error is DeviceException
            ? 'Unexpected device response. Check the address and firmware.'
            : error is TimeoutException
            ? 'The ESP32 did not respond. Check power and Wi-Fi.'
            : 'Could not reach the ESP32. Check power and Wi-Fi.';
      });
      if (userInitiated) _haptics.error();
    } finally {
      if (mounted && api == _api) {
        setState(() {
          _checking = false;
          _userChecking = false;
        });
        _scheduleRefresh(immediate: generation != _statusGeneration);
      }
    }
  }

  Future<void> _unlock() async {
    final api = _api;
    if (api == null || !_online || _unlocking || _deviceState == 'unlocking') {
      return;
    }
    setState(() => _unlocking = true);
    // A status request sent before this command cannot describe its outcome.
    _statusGeneration++;
    _pollTimer?.cancel();
    _haptics.tap();
    try {
      await api.unlockDoor(relayMode: _relayMode, unlockKeyHex: _unlockKey);
      if (!mounted || api != _api) return;
      setState(() {
        _pairingError = false;
        _deviceState = 'unlocking';
      });
      // The device accepted the command; this is not a door-sensor reading.
      _haptics.success();
    } on DeviceException catch (error) {
      if (mounted && api == _api) {
        _haptics.error();
        _showMessage(
          error.statusCode == 401
              ? 'Pairing key rejected. Update it in device settings.'
              : error.statusCode == 409
              ? 'The device is already unlocking. Try again shortly.'
              : error.statusCode == 503
              ? 'Device busy or unavailable. Try again shortly.'
              : 'Could not unlock. Check your device and try again.',
        );
        if (error.statusCode == 401) {
          setState(() => _pairingError = true);
        } else if (error.statusCode != 409) {
          setState(() => _online = false);
        }
      }
    } catch (_) {
      if (mounted && api == _api) {
        _haptics.error();
        _showMessage('No confirmation. Check the device before retrying.');
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
    _settingsOpen = true;
    _api?.discardPreparedUnlock();
    _statusGeneration++;
    _pollTimer?.cancel();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          settings: _settings,
          haptics: _haptics,
          themeMode: widget.themeMode,
        ),
      ),
    );
    _settingsOpen = false;
    if (!mounted) return;
    setState(() {
      _online = false;
      _hasChecked = false;
    });
    // A key can have been saved even if saving the address then failed.
    // Reload on every return so another page cannot leave control using an old key.
    try {
      final address = await _settings.loadAddress();
      final savedKey = await _loadOptionalKey(address);
      if (!mounted) return;
      setState(() {
        _connect(address);
        _unlockKey = savedKey;
      });
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _connect(null);
          _settingsError = true;
          _hasChecked = true;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final recovering =
        !_online && _connectionFailures > 0 && _connectionFailures < 3;
    final connectionLabel = _hasConnected ? 'Reconnecting…' : 'Connecting…';
    final stateLabel = _address == null
        ? 'Not connected'
        : recovering
        ? connectionLabel
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
        : recovering
        ? connectionLabel
        : !_online
        ? 'Offline'
        : !ready
        ? 'Setup needed'
        : 'Online';
    final helperText = _settingsError
        ? 'Could not load device settings. Open Settings to try again.'
        : _address == null
        ? 'Add device address'
        : recovering
        ? 'Retrying automatically…'
        : !_online
        ? _connectionIssue ??
              'Could not reach the ESP32. Check power and Wi-Fi.'
        : _relayMode && !_armed
        ? 'Set a pairing key on your device.'
        : _pairingError
        ? 'Pairing key rejected'
        : _relayMode && _unlockKey == null
        ? 'Add a pairing key in Settings.'
        : null;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            // Reserve room for the header, connection row and card content.
            final controlSize = compact
                ? 200.0
                : (constraints.maxHeight - 560).clamp(224.0, 320.0);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 32,
                24,
                compact ? 20 : 32,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 560 : 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              color: colors.onPrimary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'LockLink',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Device settings',
                            onPressed: _loading ? null : _editAddress,
                            icon: const Icon(Icons.tune_rounded, size: 22),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 40 : 56),
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 560 : 840,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DoorControlCard(
                                connectionError:
                                    !_loading &&
                                    _hasChecked &&
                                    !_online &&
                                    !recovering,
                                online: _online,
                                ready: ready,
                                active: active,
                                stateLabel: _loading
                                    ? 'Connecting…'
                                    : !_hasChecked && _address != null
                                    ? connectionLabel
                                    : stateLabel,
                                statusText: _loading || !_hasChecked
                                    ? 'Connecting'
                                    : statusText,
                                helperText: _loading || !_hasChecked
                                    ? null
                                    : helperText,
                                onUnlock: ready ? _unlock : null,
                                compact: compact,
                                controlSize: controlSize,
                              ),
                              const SizedBox(height: 16),
                              if (_loading)
                                const LinearProgressIndicator()
                              else if (_address == null)
                                OutlinedButton.icon(
                                  onPressed: _editAddress,
                                  icon: Icon(
                                    _settingsError
                                        ? Icons.tune_rounded
                                        : Icons.add_rounded,
                                  ),
                                  label: Text(
                                    _settingsError
                                        ? 'Open Settings'
                                        : 'Connect device',
                                  ),
                                )
                              else
                                Material(
                                  color: colors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(20),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 6,
                                    ),
                                    leading: Icon(
                                      Icons.router_outlined,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    title: const Text('Connection'),
                                    subtitle: Text(
                                      _address!.replaceFirst('http://', ''),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Check connection',
                                      onPressed: _checking || _unlocking
                                          ? null
                                          : () => _refresh(userInitiated: true),
                                      icon:
                                          _checking &&
                                              (!_online || _userChecking)
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.refresh_rounded),
                                    ),
                                    onTap: _editAddress,
                                  ),
                                ),
                              if (!_loading &&
                                  _hasChecked &&
                                  !_online &&
                                  !recovering &&
                                  !_settingsError) ...[
                                const SizedBox(height: 12),
                                const DeviceConnectionHelp(),
                              ],
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.wifi_rounded,
                                    size: 14,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _relayMode
                                          ? 'Local Wi-Fi · Lock control'
                                          : 'Local Wi-Fi · LED prototype',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
