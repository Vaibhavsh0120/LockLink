import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_settings.dart';
import '../services/terminal_session.dart';
import '../widgets/pairing_code_display.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.settings});
  final DeviceSettings settings;
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  late final TerminalSession _session;
  final _command = TextEditingController();
  final _scroll = ScrollController();
  bool _follow = true;
  int _lineCount = 0;
  List<String>? _readingLines;

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
    if (!mounted) return;
    if (_session.pairingCode == null && _readingLines != null) {
      _readingLines = _readingLines!
          .map(
            (line) => line.replaceAll(
              RegExp(r'Code: \d{11,21}'),
              'Code: hidden. Run PAIR to view.',
            ),
          )
          .toList();
    }
    final changed = _lineCount != _session.lines.length;
    _lineCount = _session.lines.length;
    setState(() {});
    if (_follow && (changed || _session.lines.length == 300)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _resumeFollowing() {
    _readingLines = null;
    _follow = true;
    _lineCount = -1;
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setActive(state == AppLifecycleState.resumed);

  Future<void> _send([String? command]) async {
    final value = command ?? _command.text;
    if (value.trim().isEmpty || _session.busy || !_session.connected) return;
    final result = await _session.send(value);
    if (mounted && result != null && command == null) _command.clear();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: (_readingLines ?? _session.lines).join('\n')),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Terminal copied.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not copy. Select text to copy manually.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    _command.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = _session.connected && !_session.busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Terminal options',
            onSelected: (value) {
              if (value == 'copy') _copy();
              if (value == 'clear') {
                _readingLines = null;
                _follow = true;
                _session.clear();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy',
                enabled: _session.lines.isNotEmpty,
                child: const Text('Copy terminal'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear terminal'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: SizedBox(
                  height: math.max(
                    constraints.maxHeight,
                    MediaQuery.textScalerOf(context).scale(360),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _session.connected
                                  ? Icons.wifi_rounded
                                  : Icons.wifi_off_rounded,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _session.error ??
                                    (_session.connected
                                        ? 'Live · ${_session.address.replaceFirst('http://', '')}'
                                        : 'Connecting…'),
                              ),
                            ),
                            if (_session.error != null)
                              IconButton(
                                tooltip: 'Reconnect',
                                onPressed: _session.busy
                                    ? null
                                    : () => _session.send('STATUS'),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Device logs over Wi-Fi. Bootloader logs require USB.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (_session.pairingCode != null)
                          OutlinedButton.icon(
                            onPressed: () => showPairingQr(context, _session),
                            icon: const Icon(Icons.qr_code_rounded),
                            label: const Text('Show pairing QR'),
                          ),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: NotificationListener<UserScrollNotification>(
                              onNotification: (_) {
                                final follow =
                                    _scroll.position.extentAfter < 48;
                                if (!follow && _follow) {
                                  setState(() {
                                    _follow = false;
                                    _readingLines = List.of(_session.lines);
                                  });
                                } else if (follow && !_follow) {
                                  _resumeFollowing();
                                }
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: _scroll,
                                padding: const EdgeInsets.all(16),
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: SelectableText(
                                    (_readingLines ?? _session.lines).isEmpty
                                        ? 'Waiting for device logs…'
                                        : (_readingLines ?? _session.lines)
                                              .join('\n'),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'monospace',
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (!_follow)
                          TextButton(
                            onPressed: _resumeFollowing,
                            child: const Text('Resume live logs'),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PopupMenuButton<String>(
                            tooltip: 'Choose command',
                            enabled: canSend,
                            onSelected: _send,
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'HELP',
                                child: Text('HELP · List commands'),
                              ),
                              PopupMenuItem(
                                value: 'STATUS',
                                child: Text('STATUS · Device state'),
                              ),
                              PopupMenuItem(
                                value: 'PAIR',
                                child: Text('PAIR · Setup code'),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Commands',
                                    style: TextStyle(
                                      color: canSend
                                          ? null
                                          : theme.disabledColor,
                                    ),
                                  ),
                                  Icon(
                                    Icons.expand_more_rounded,
                                    color: canSend ? null : theme.disabledColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                enabled: _session.connected,
                                controller: _command,
                                maxLength: 64,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.send,
                                decoration: const InputDecoration(
                                  labelText: 'Command',
                                  hintText: 'Connect, then type HELP',
                                  counterText: '',
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filled(
                              tooltip: 'Send command',
                              onPressed: _session.busy || !_session.connected
                                  ? null
                                  : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
