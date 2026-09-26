import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import 'app_theme.dart';
import '../services/device_settings.dart';

class LockLinkApp extends StatefulWidget {
  const LockLinkApp({
    super.key,
    required this.settings,
    this.initialThemeMode = ThemeMode.system,
  });

  final DeviceSettings settings;
  final ThemeMode initialThemeMode;

  @override
  State<LockLinkApp> createState() => _LockLinkAppState();
}

class _LockLinkAppState extends State<LockLinkApp> {
  late final _themeMode = ValueNotifier(widget.initialThemeMode);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: _themeMode,
    builder: (context, mode, child) => MaterialApp(
      title: 'LockLink',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      home: HomeScreen(settings: widget.settings, themeMode: _themeMode),
    ),
  );
}
