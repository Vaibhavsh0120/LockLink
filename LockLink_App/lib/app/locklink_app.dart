import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
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

  ThemeData _theme(Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF303030),
      brightness: brightness,
    );
    final scheme = brightness == Brightness.dark
        ? baseScheme.copyWith(
            primary: const Color(0xFFF2F2F2),
            onPrimary: const Color(0xFF202020),
            primaryContainer: const Color(0xFF383838),
            onPrimaryContainer: const Color(0xFFF2F2F2),
            surface: const Color(0xFF121212),
            onSurface: const Color(0xFFF2F2F2),
            surfaceContainerLow: const Color(0xFF1E1E1E),
            surfaceContainerHighest: const Color(0xFF303030),
            onSurfaceVariant: const Color(0xFFBDBDBD),
            outline: const Color(0xFF888888),
          )
        : baseScheme.copyWith(
            primary: const Color(0xFF292929),
            onPrimary: Colors.white,
            surface: const Color(0xFFF7F7F7),
            surfaceContainerLow: Colors.white,
            surfaceContainerHighest: const Color(0xFFE8E8E8),
          );
    final baseTheme = ThemeData(useMaterial3: true, colorScheme: scheme);
    return baseTheme.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: baseTheme.textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: _themeMode,
    builder: (context, mode, child) => MaterialApp(
      title: 'LockLink',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeScreen(settings: widget.settings, themeMode: _themeMode),
    ),
  );
}
