import 'package:flutter/material.dart';

/// Shared Material styling, aligned with the native gate widgets.
abstract final class AppTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF526057),
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFE2EADB) : const Color(0xFF222823),
          onPrimary: dark ? const Color(0xFF222823) : const Color(0xFFF6F4EF),
          primaryContainer: dark
              ? const Color(0xFF303D32)
              : const Color(0xFFE7ECE2),
          onPrimaryContainer: dark
              ? const Color(0xFFE2EADB)
              : const Color(0xFF303D32),
          secondaryContainer: dark
              ? const Color(0xFF303A32)
              : const Color(0xFFEAECE5),
          onSecondaryContainer: dark
              ? const Color(0xFFE2EADB)
              : const Color(0xFF222823),
          surface: dark ? const Color(0xFF141A16) : const Color(0xFFF6F4EF),
          onSurface: dark ? const Color(0xFFF3F3EB) : const Color(0xFF222823),
          surfaceContainerLow: dark
              ? const Color(0xFF202722)
              : const Color(0xFFFFFEFA),
          surfaceContainerHighest: dark
              ? const Color(0xFF303A32)
              : const Color(0xFFEAECE5),
          onSurfaceVariant: dark
              ? const Color(0xFFB5C2B7)
              : const Color(0xFF526057),
          outline: dark ? const Color(0xFF869789) : const Color(0xFF707C72),
          outlineVariant: dark
              ? const Color(0xFF414D43)
              : const Color(0xFFD5DBD4),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      scaffoldBackgroundColor: scheme.surface,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          visualDensity: VisualDensity.standard,
        ),
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        helperMaxLines: 2,
        errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          shape: shape,
          textStyle: base.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          visualDensity: VisualDensity.standard,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 32,
      ),
    );
  }
}
