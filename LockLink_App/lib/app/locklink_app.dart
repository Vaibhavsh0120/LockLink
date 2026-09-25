import 'package:flutter/material.dart';

import '../screens/home_screen.dart';

class LockLinkApp extends StatelessWidget {
  const LockLinkApp({super.key});

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
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LockLink',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const HomeScreen(),
  );
}
