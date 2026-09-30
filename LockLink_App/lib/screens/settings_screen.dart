import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../services/device_settings.dart';
import '../services/widget_bridge.dart';
import 'terminal_screen.dart';
import 'smart_home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.haptics,
    required this.themeMode,
  });

  final DeviceSettings settings;
  final AppHaptics haptics;
  final ValueNotifier<ThemeMode> themeMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _pairingKey = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _savingPreference = false;
  bool _showKey = false;
  String? _loadError;
  bool _updatingWidgets = false;
  String? _widgetMessage;

  Future<void> _updateWidgets() async {
    setState(() {
      _updatingWidgets = true;
      _widgetMessage = null;
    });
    try {
      await WidgetBridge.synchronize(widget.settings);
      final pinned = await WidgetBridge.requestPin();
      if (!mounted) return;
      setState(
        () => _widgetMessage = pinned ? 'Confirm on your Home Screen.' : 'Widget settings updated. Hold your Home Screen, then choose Widgets → LockLink. iPhone also supports Lock Screen and Today View.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _widgetMessage = WidgetBridge.setupFailureMessage(error));
    } finally {
      if (mounted) setState(() => _updatingWidgets = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final address = await widget.settings.loadAddress();
      final key = await widget.settings.loadPairingKey(address);
      if (!mounted) return;
      _address.text = address.replaceFirst('http://', '');
      _pairingKey.text = key;
    } catch (_) {
      if (!mounted) return;
      _loadError = 'Could not load device settings.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveDevice() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      widget.haptics.error();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final address = DeviceSettings.normalizeAddress(_address.text)!;
    try {
      // Save the credential first so a failed write cannot select an unpaired device.
      await widget.settings.saveUnlockKey(address, _pairingKey.text);
      await widget.settings.saveAddress(address);
      var widgetsUpdated = true;
      try {
        await WidgetBridge.synchronize(widget.settings);
      } catch (_) {
        widgetsUpdated = false;
      }
      if (!mounted) return;
      widget.haptics.success();
      setState(() => _saving = false);
      _message(
        widgetsUpdated ? 'Device settings saved.' : 'Device saved. Widgets were not updated. Open widget setup for details.',
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      widget.haptics.error();
      _message('Could not save. Try again.');
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    if (_savingPreference || widget.themeMode.value == mode) return;
    final previous = widget.themeMode.value;
    setState(() => _savingPreference = true);
    widget.themeMode.value = mode;
    widget.haptics.selection();
    try {
      await widget.settings.saveThemeMode(mode);
    } catch (_) {
      widget.themeMode.value = previous;
      if (mounted) _message('Could not save appearance. Please try again.');
    } finally {
      if (mounted) setState(() => _savingPreference = false);
    }
  }

  Future<void> _setHaptics(bool enabled) async {
    if (_savingPreference) return;
    final previous = widget.haptics.enabled;
    setState(() {
      _savingPreference = true;
      widget.haptics.enabled = enabled;
    });
    widget.haptics.selection();
    try {
      await widget.settings.saveHapticsEnabled(enabled);
    } catch (_) {
      widget.haptics.enabled = previous;
      if (mounted) {
        _message('Could not save haptic feedback. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _savingPreference = false);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _pairingKey.dispose();
    super.dispose();
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _deviceSection(bool busy) => _section(
    'Device',
    Icons.router_outlined,
    [
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_loadError != null) ...[
        Text(_loadError!),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ] else
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect on the same Wi-Fi.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _address,
                enabled: !busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Device IP address',
                  hintText: '192.168.0.111',
                ),
                validator: (value) =>
                    DeviceSettings.normalizeAddress(value ?? '') == null
                    ? 'Enter a local IP or http:// address'
                    : null,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _pairingKey,
                enabled: !busy,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveDevice(),
                decoration: InputDecoration(
                  labelText: 'Pairing key',
                  helperText: 'Use the key set on your device.',
                  suffixIcon: IconButton(
                    tooltip: _showKey ? 'Hide pairing key' : 'Show pairing key',
                    onPressed: busy
                        ? null
                        : () => setState(() => _showKey = !_showKey),
                    icon: Icon(
                      _showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  try {
                    DeviceSettings.signingKey(value ?? '');
                    return null;
                  } on FormatException {
                    return 'Use 4 to 64 characters';
                  }
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : _saveDevice,
                child: Text(_saving ? 'Saving…' : 'Save device'),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _preferencesSection(bool busy) =>
      _section('Preferences', Icons.tune_rounded, [
        const Text('Appearance'),
        const SizedBox(height: 12),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: widget.themeMode,
          builder: (context, mode, child) => LayoutBuilder(
            builder: (context, constraints) {
              // Keep every choice readable with large accessibility text.
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
              if (largeText || constraints.maxWidth < 250) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      ThemeMode.light: 'Light',
                      ThemeMode.dark: 'Dark',
                      ThemeMode.system: 'System',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: mode == entry.key,
                        onSelected: busy ? null : (_) => _setTheme(entry.key),
                      ),
                  ],
                );
              }
              return SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ],
                selected: {mode},
                onSelectionChanged: busy
                    ? null
                    : (values) => _setTheme(values.single),
              );
            },
          ),
        ),
        if (AppHaptics.supported) ...[
          const Divider(),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Haptic feedback'),
            subtitle: const Text('Vibrate on taps and actions'),
            value: widget.haptics.enabled,
            onChanged: busy ? null : _setHaptics,
          ),
        ],
      ]);

  Widget _widgetsSection(bool busy) => _section(
    'Home screen',
    Icons.widgets_outlined,
    [
      Text(
        'Unlock from a widget on the same Wi-Fi.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: busy || _loading ? null : _updateWidgets,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(_updatingWidgets ? 'Updating…' : 'Set up widgets'),
      ),
      if (_widgetMessage != null) ...[
        const SizedBox(height: 16),
        Semantics(liveRegion: true, child: Text(_widgetMessage!)),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _savingPreference || _updatingWidgets;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final wide = constraints.maxWidth >= 840;
              final preferences = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _preferencesSection(busy),
                  const SizedBox(height: 16),
                  _section('Device tools', Icons.build_outlined, [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.terminal_rounded),
                      title: const Text('Terminal'),
                      subtitle: const Text('Live logs and commands'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      enabled: !busy && !_loading,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TerminalScreen(settings: widget.settings),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Smart home setup'),
                      subtitle: const Text(
                        'Apple Home, Google Home, Alexa · Optional',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      enabled: !busy && !_loading,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SmartHomeScreen(settings: widget.settings),
                        ),
                      ),
                    ),
                    const Text(
                      'Uses your saved device address and pairing key.',
                    ),
                  ]),
                  if (!wide && WidgetBridge.supported) ...[
                    const SizedBox(height: 16),
                    _widgetsSection(busy),
                  ],
                ],
              );
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 32,
                  24,
                  compact ? 20 : 32,
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide
                          ? 1120
                          : compact
                          ? 560
                          : 800,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton.outlined(
                              tooltip: 'Back',
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Settings',
                                style: theme.textTheme.headlineMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _deviceSection(busy),
                                    if (WidgetBridge.supported) ...[
                                      const SizedBox(height: 16),
                                      _widgetsSection(busy),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(child: preferences),
                            ],
                          )
                        else ...[
                          _deviceSection(busy),
                          const SizedBox(height: 16),
                          preferences,
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'LockLink · v1.5.0',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
      ),
    );
  }
}
