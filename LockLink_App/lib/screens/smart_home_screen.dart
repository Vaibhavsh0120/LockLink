import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/matter_home.dart';

import '../services/device_settings.dart';
import '../services/home_app_launcher.dart';
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

class SmartHomeScreen extends StatefulWidget {
  const SmartHomeScreen({super.key, required this.settings});
  final DeviceSettings settings;
  @override
  State<SmartHomeScreen> createState() => _SmartHomeScreenState();
}

class _SmartHomeScreenState extends State<SmartHomeScreen>
    with WidgetsBindingObserver {
  late final TerminalSession _session;
  bool _visible = true;
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
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setActive(_visible && state == AppLifecycleState.resumed);

  Future<void> _open(HomeEcosystem home) async {
    _visible = false;
    _session.setActive(false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HomeSetupScreen(settings: widget.settings, ecosystem: home),
      ),
    );
    if (!mounted) return;
    _visible = true;
    _result = null;
    _session.setActive(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  Future<void> _chooseHome() async {
    final home = await showModalBottomSheet<HomeEcosystem>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose a home app',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final home in HomeEcosystem.values)
                ListTile(
                  leading: Icon(home.icon),
                  title: Text(home.label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, home),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && home != null) await _open(home);
  }

  Future<void> _changeHome(MatterHome home, bool remove) async {
    if (!_session.connected || _session.sendingCommand) return;
    String? command;
    if (remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove ${home.displayName}?'),
          content: Text(
            'Everyone using this home will lose access to the door. Wi-Fi, other homes, and LockLink app access stay connected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove home'),
            ),
          ],
        ),
      );
      if (confirmed == true) command = 'HOME REMOVE ${home.id}';
    } else {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RenameHomeDialog(label: home.label),
      );
      if (name != null) {
        final hex = utf8
            .encode(name)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        command = 'HOME NAME ${home.id} $hex';
      }
    }
    if (!mounted || command == null || !_session.connected) return;
    final result = await _session.send(command);
    if (mounted) {
      setState(
        () => _result =
            result?.output ??
            _session.error ??
            'No confirmed reply. Refresh before trying again.',
      );
    }
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
    final latest = _session.latest;
    final homes = _session.connected ? latest?.homes : null;
    final busy = !_session.connected || _session.sendingCommand;
    final full = homes != null && homes.length >= (latest?.fabricCapacity ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart home setup'),
        actions: [
          IconButton(
            tooltip: 'Refresh connected homes',
            onPressed: _session.sendingCommand
                ? null
                : () => _session.send('HOMES'),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
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
                    'Connected homes',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One pairing per home. Phones and people sharing that home use the same pairing.',
                  ),
                  const SizedBox(height: 20),
                  if (!_session.connected) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _session.error ?? 'Connecting to your door…',
                        style: _session.error == null
                            ? null
                            : TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                      ),
                    ),
                    if (_session.error != null) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _session.sendingCommand
                            ? null
                            : () => _session.send('STATUS'),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry connection'),
                      ),
                      const DeviceConnectionHelp(),
                    ],
                  ] else if (homes == null)
                    const Text(
                      'Update the ESP32 firmware to view, rename, or remove connected homes.',
                    )
                  else if (homes.isEmpty)
                    const Text('No homes paired. Choose a home app below.')
                  else
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < homes.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              leading: const Icon(Icons.home_outlined),
                              title: Text(homes[i].displayName),
                              subtitle: Text(
                                homes[i].label.isEmpty
                                    ? 'Connected'
                                    : homes[i].platform,
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: 'Manage ${homes[i].displayName}',
                                enabled: !busy,
                                onSelected: (value) =>
                                    _changeHome(homes[i], value == 'remove'),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove home'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_session.connected &&
                      latest?.pairingMode == 'additional' &&
                      latest?.pairingWindowOpen == true) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final result = await _session.send('PAIR CLOSE');
                              if (mounted) {
                                setState(
                                  () => _result =
                                      result?.output ?? _session.error,
                                );
                              }
                            },
                      child: const Text('Close pairing window'),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Semantics(liveRegion: true, child: Text(_result!)),
                  ],
                  const SizedBox(height: 24),
                  if (homes != null && homes.isNotEmpty) ...[
                    if (full)
                      const Text(
                        'Connected homes are full. Remove an unused home first.',
                      ),
                    FilledButton.icon(
                      onPressed: full ? null : _chooseHome,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add home app'),
                    ),
                  ] else ...[
                    Text(
                      'Choose a home app',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    for (final home in HomeEcosystem.values) ...[
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: Icon(home.icon),
                          title: Text(home.label),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(home),
                        ),
                      ),
                      if (home != HomeEcosystem.values.last)
                        const SizedBox(height: 12),
                    ],
                  ],
                  const SizedBox(height: 24),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Sharing across devices'),
                    children: const [
                      Text(
                        'Invite people in Apple Home Settings to share one home. LockLink cannot list Apple Accounts or manage those invitations.',
                      ),
                      SizedBox(height: 12),
                      Text(
                        'LockLink apps refresh from the door on the same Wi-Fi. Use the same device address and app pairing key on each phone.',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameHomeDialog extends StatefulWidget {
  const _RenameHomeDialog({required this.label});
  final String label;
  @override
  State<_RenameHomeDialog> createState() => _RenameHomeDialogState();
}

class _RenameHomeDialogState extends State<_RenameHomeDialog> {
  late final _controller = TextEditingController(text: widget.label);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename home'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _controller,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Home name'),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Enter a home name.';
              if (utf8.encode(text).length > 32 ||
                  text.runes.any((r) => r < 32 || r == 127)) {
                return 'Name is too long. Try a shorter name.';
              }
              return null;
            },
          ),
          const Text(
            'This name syncs between LockLink apps. Your home app may keep its own name.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Save'),
      ),
    ],
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
  bool _checking = false;
  bool _openingHome = false;
  bool _prepared = false;
  Set<String>? _baselineHomes;
  String? _baselineBoot;
  bool? _baselineCommissioned;
  String? _result;
  bool _resultError = false;
  String? _launchError;

  bool get _commandBusy => _session.sendingCommand || _preparing || _checking;

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
        if (_baselineBoot != null && _session.boot != _baselineBoot) {
          _result =
              'Door restarted. Get a fresh code before checking a new pairing.';
          _resultError = false;
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.setActive(state == AppLifecycleState.resumed);
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    if (!_session.connected || _commandBusy || _openingHome) return;
    setState(() {
      _preparing = true;
      _result = null;
      _resultError = false;
      _baselineHomes = null;
      _baselineBoot = null;
      _baselineCommissioned = null;
    });
    try {
      final status = await _session.send('STATUS');
      if (!mounted || status == null) return;
      if (!status.ok || (status.commissioned && status.homes == null)) {
        setState(() {
          _result = status.ok
              ? 'Update the ESP32 firmware to get a sharing code here.'
              : status.output;
          _resultError = true;
        });
        return;
      }
      final reply = await _session.send(
        status.commissioned ? 'PAIR ADD' : 'PAIR',
      );
      if (mounted && reply != null) {
        setState(() {
          if (!reply.ok) {
            _result = reply.output;
            _resultError = true;
          }
          if (_session.pairingCode != null) {
            _prepared = true;
            // Another phone may add a home between STATUS and PAIR ADD.
            // Compare against the snapshot that actually opened the window.
            _baselineHomes = reply.homes?.map((home) => home.id).toSet();
            _baselineBoot = reply.boot;
            _baselineCommissioned = reply.commissioned;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _check() async {
    if (!_session.connected || _commandBusy || _openingHome) return;
    setState(() => _checking = true);
    try {
      final status = await _session.send('STATUS');
      if (!mounted || status == null) return;
      setState(() {
        _resultError = !status.ok;
        if (!status.ok) {
          _result = status.output;
        } else if (_baselineBoot != null && status.boot != _baselineBoot) {
          _result =
              'Door restarted. Get a fresh code before checking a new pairing.';
        } else if (_baselineHomes != null && status.homes != null) {
          final added = status.homes!.any(
            (home) => !_baselineHomes!.contains(home.id),
          );
          _result = added
              ? 'Matter pairing detected. Confirm Door Release appears in ${widget.ecosystem.label}.'
              : 'No new pairing detected yet. Finish setup in ${widget.ecosystem.label}.';
        } else if (_baselineCommissioned == false && status.commissioned) {
          _result =
              'Matter pairing detected. Confirm Door Release appears in ${widget.ecosystem.label}.';
        } else {
          _result = status.commissioned
              ? 'Already paired with a home. Confirm Door Release appears in ${widget.ecosystem.label}; this does not confirm a new pairing.'
              : 'No new pairing detected yet. Finish setup in ${widget.ecosystem.label}.';
        }
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openHomeApp() async {
    if (_openingHome || _commandBusy) return;
    setState(() {
      _openingHome = true;
      _launchError = null;
    });
    final home = widget.ecosystem;
    final result = await HomeAppLauncher.open(
      home.name,
      pairingQr: _session.connected ? _session.pairingQrPayload : null,
    );
    if (!mounted) return;
    setState(() {
      _openingHome = false;
      if (result == HomeAppOpenResult.unavailable) {
        _launchError =
            'Could not open ${home.label}. Install or update it, or open it yourself and follow the setup steps.';
      }
    });
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
    final legacyPaired = paired && _session.latest?.homes == null;
    final busy = _commandBusy || _openingHome || !_session.connected;
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
                    child: Text(
                      _session.error ?? 'Connecting to your ESP32…',
                      style: _session.error == null
                          ? null
                          : TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  if (_session.error != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _session.sendingCommand
                          ? null
                          : () => _session.send('STATUS'),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry connection'),
                    ),
                    const DeviceConnectionHelp(),
                  ],
                  const SizedBox(height: 16),
                ],
                if (legacyPaired) ...[
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
                        _preparing
                            ? 'Getting code…'
                            : paired
                            ? 'Get sharing code'
                            : 'Get setup code',
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
                    Text(
                      paired
                          ? 'The sharing window lasts up to 5 minutes. Return here to check pairing.'
                          : 'Then return here to check pairing.',
                    ),
                    if (_session.latest?.pairingMode == 'additional')
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _session.send('PAIR CLOSE'),
                        child: const Text('Close pairing window'),
                      ),
                  ] else if (_prepared) ...[
                    const Text(
                      'Setup code hidden. Check pairing or get the code again.',
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed:
                      !HomeAppLauncher.supports(home.name) ||
                          _commandBusy ||
                          _openingHome
                      ? null
                      : _openHomeApp,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(_openingHome ? 'Opening…' : 'Open ${home.label}'),
                ),
                const SizedBox(height: 8),
                if (!HomeAppLauncher.supports(home.name))
                  Text(
                    home == HomeEcosystem.apple
                        ? 'Finish setup in Apple Home on an iPhone or iPad.'
                        : 'Finish setup in the home app on a phone.',
                  ),
                if (_launchError != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _launchError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                if (_prepared || legacyPaired) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : _check,
                    child: const Text('Check pairing'),
                  ),
                  if (!legacyPaired && _session.pairingCode == null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: busy ? null : _prepare,
                      child: Text(
                        _preparing ? 'Getting code…' : 'Get code again',
                      ),
                    ),
                  ],
                ],
                if (_result != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _result!,
                      style: _resultError
                          ? TextStyle(color: theme.colorScheme.error)
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!_prepared && !legacyPaired)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Setup steps'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(home.instructions),
                      ),
                    ],
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('About Door Release'),
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Door Release is a Matter door lock. Unlock releases for 2 seconds; Lock stops it early. Its status reports the output, not the physical door position.',
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
