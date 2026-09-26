import 'package:flutter/material.dart';

import '../services/app_haptics.dart';
import '../services/device_settings.dart';

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
      if (!mounted) return;
      widget.haptics.success();
      setState(() => _saving = false);
      _message('Device settings saved.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      widget.haptics.error();
      _message('Could not save device settings. Please try again.');
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

  Widget _section(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _savingPreference;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section('Device', [
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_loadError != null) ...[
                        Text(_loadError!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ] else
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Use the same Wi-Fi as your device.'),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _address,
                                enabled: !busy,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Device IP address',
                                  hintText: '192.168.0.111',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    DeviceSettings.normalizeAddress(
                                          value ?? '',
                                        ) ==
                                        null
                                    ? 'Enter a local IP address or http:// address'
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
                                  helperText:
                                      'Use the same key as your device.',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    tooltip: _showKey
                                        ? 'Hide pairing key'
                                        : 'Show pairing key',
                                    onPressed: () =>
                                        setState(() => _showKey = !_showKey),
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
                                child: Text(
                                  _saving ? 'Saving…' : 'Save device',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ]),
                    const SizedBox(height: 24),
                    _section('Appearance', [
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: widget.themeMode,
                        builder: (context, mode, child) =>
                            SegmentedButton<ThemeMode>(
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                selectedForegroundColor: Theme.of(context)
                                    .colorScheme
                                    .onPrimary,
                              ),
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('System'),
                                ),
                              ],
                              selected: {mode},
                              onSelectionChanged: busy
                                  ? null
                                  : (values) => _setTheme(values.single),
                            ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Saved automatically. System follows your device theme.',
                      ),
                    ]),
                    if (AppHaptics.supported) ...[
                      const SizedBox(height: 24),
                      _section('Haptics', [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Haptic feedback'),
                          subtitle: const Text(
                            'Vibrate for taps and action results. Saved automatically.',
                          ),
                          value: widget.haptics.enabled,
                          onChanged: busy ? null : _setHaptics,
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
