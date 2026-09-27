import 'package:flutter/material.dart';

import '../services/device_settings.dart';
import '../services/terminal_session.dart';
import '../widgets/pairing_code_display.dart';
import '../widgets/device_connection_help.dart';

enum HomeEcosystem {
  apple(
    'Apple Home',
    Icons.home_outlined,
    'Use an iPhone with Bluetooth enabled and the Home app.',
    'Open Home, tap +, then Add Accessory. Scan the QR, or choose More Options to enter the code.',
  ),
  google(
    'Google Home',
    Icons.home_work_outlined,
    'Use Google Home and a compatible Matter hub. This development board also needs a test integration with its VID/PID and an authorized tester account.',
    'In Google Home, open Devices and add a Matter-enabled device. Scan the QR, or choose Set up without QR code.',
  ),
  alexa(
    'Amazon Alexa',
    Icons.record_voice_over_outlined,
    'Use Alexa and a compatible Echo Matter controller. Development-device acceptance may require Amazon’s Matter test setup.',
    'In Alexa, open Devices, tap +, then Add Device. Choose Other, then Matter. Scan the QR or enter the code.',
  );

  const HomeEcosystem(
    this.label,
    this.icon,
    this.requirements,
    this.instructions,
  );
  final String label;
  final IconData icon;
  final String requirements;
  final String instructions;
}

class SmartHomeScreen extends StatelessWidget {
  const SmartHomeScreen({super.key, required this.settings});
  final DeviceSettings settings;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Smart home setup')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose a home app',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Optional setup for Door Release.'),
                const SizedBox(height: 24),
                for (final home in HomeEcosystem.values) ...[
                  Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: Icon(home.icon),
                      title: Text(home.label),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeSetupScreen(
                            settings: settings,
                            ecosystem: home,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (home != HomeEcosystem.values.last)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 24),
                const Text('Power on your ESP32 and use the same Wi-Fi.'),
                const SizedBox(height: 8),
                const DeviceConnectionHelp(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeSetupScreen extends StatefulWidget {
  const HomeSetupScreen({
    super.key,
    required this.settings,
    required this.ecosystem,
  });
  final DeviceSettings settings;
  final HomeEcosystem ecosystem;
  @override
  State<HomeSetupScreen> createState() => _HomeSetupScreenState();
}

class _HomeSetupScreenState extends State<HomeSetupScreen>
    with WidgetsBindingObserver {
  late final TerminalSession _session;
  bool _preparing = false;
  bool _prepared = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = TerminalSession(widget.settings)..addListener(_changed);
    _session.setActive(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _session.start();
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (!_session.connected) _result = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.setActive(state == AppLifecycleState.resumed);
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    if (!_session.connected || _session.busy || _preparing) return;
    setState(() {
      _preparing = true;
      _result = null;
    });
    try {
      final status = await _session.send('STATUS');
      if (!mounted || status == null || !status.ok || status.commissioned) {
        return;
      }
      final reply = await _session.send('PAIR');
      if (mounted && reply != null) {
        setState(() {
          if (!reply.ok) _result = reply.output;
          if (_session.pairingCode != null) _prepared = true;
        });
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _check() async {
    if (!_session.connected) return;
    final status = await _session.send('STATUS');
    if (!mounted || status == null) return;
    setState(
      () => _result = status.commissioned
          ? 'Matter pairing detected. Confirm Door Release appears in ${widget.ecosystem.label}.'
          : 'Not paired yet. Finish setup in ${widget.ecosystem.label}.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.ecosystem;
    final paired = _session.latest?.commissioned == true;
    final busy = _session.busy || _preparing || !_session.connected;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(home.label),
        actions: [
          if (_session.pairingCode != null)
            PopupMenuButton<String>(
              tooltip: 'Pairing options',
              enabled: !busy,
              onSelected: (_) => _prepare(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('Get code again')),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add Door Release', style: theme.textTheme.headlineSmall),
                if (!_prepared) ...[
                  const SizedBox(height: 12),
                  Text(home.requirements),
                ],
                const SizedBox(height: 20),
                if (!_session.connected) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(_session.error ?? 'Connecting to your ESP32…'),
                  ),
                  if (_session.error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _session.busy
                          ? null
                          : () => _session.send('STATUS'),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry connection'),
                    ),
                    const DeviceConnectionHelp(),
                  ],
                  const SizedBox(height: 16),
                ],
                if (paired) ...[
                  Text('Already paired', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'In the connected home app, open Door Release’s Matter sharing or pairing settings. Get a fresh code there, then add it to this home app.',
                  ),
                  const SizedBox(height: 12),
                  Text(home.instructions),
                ] else ...[
                  if (!_prepared)
                    FilledButton.icon(
                      onPressed: busy ? null : _prepare,
                      icon: const Icon(Icons.qr_code_rounded),
                      label: Text(
                        _preparing ? 'Getting code…' : 'Get setup code',
                      ),
                    ),
                  if (_session.pairingCode != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: PairingCodeDisplay(session: _session),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Finish in ${home.label}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(home.instructions),
                    const SizedBox(height: 8),
                    const Text('Then return here to check pairing.'),
                  ] else if (_prepared) ...[
                    const Text(
                      'Setup code hidden. Check pairing or get the code again.',
                    ),
                  ],
                  if (_prepared) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _check,
                      child: const Text('Check pairing'),
                    ),
                    if (_session.pairingCode == null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: busy ? null : _prepare,
                        child: Text(
                          _preparing ? 'Getting code…' : 'Get code again',
                        ),
                      ),
                    ],
                  ],
                ],
                if (paired) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: busy ? null : _check,
                    child: const Text('Check pairing'),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Semantics(liveRegion: true, child: Text(_result!)),
                ],
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('About Door Release'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Door Release is a momentary switch. Turning it on releases for 2 seconds. It has no door-position sensor or spoken unlock PIN.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Device checks'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        _session.lines.isEmpty
                            ? 'Connecting…'
                            : _session.lines.join('\n'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
