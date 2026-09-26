import 'package:flutter/material.dart';

/// Shared Material styling, aligned with the native gate widgets.
abstract final class AppTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark
        ? const ColorScheme.dark(
            primary: Color(0xFFF2F2F2),
            onPrimary: Color(0xFF202020),
            primaryContainer: Color(0xFF333333),
            onPrimaryContainer: Color(0xFFF2F2F2),
            primaryFixed: Color(0xFFE5E5E5),
            primaryFixedDim: Color(0xFFC6C6C6),
            onPrimaryFixed: Color(0xFF202020),
            onPrimaryFixedVariant: Color(0xFF444444),
            secondary: Color(0xFFC6C6C6),
            onSecondary: Color(0xFF202020),
            secondaryContainer: Color(0xFF303030),
            onSecondaryContainer: Color(0xFFF2F2F2),
            secondaryFixed: Color(0xFFE5E5E5),
            secondaryFixedDim: Color(0xFFC6C6C6),
            onSecondaryFixed: Color(0xFF202020),
            onSecondaryFixedVariant: Color(0xFF444444),
            tertiary: Color(0xFFC6C6C6),
            onTertiary: Color(0xFF202020),
            tertiaryContainer: Color(0xFF333333),
            onTertiaryContainer: Color(0xFFF2F2F2),
            tertiaryFixed: Color(0xFFE5E5E5),
            tertiaryFixedDim: Color(0xFFC6C6C6),
            onTertiaryFixed: Color(0xFF202020),
            onTertiaryFixedVariant: Color(0xFF444444),
            error: Color(0xFFF2F2F2),
            onError: Color(0xFF202020),
            errorContainer: Color(0xFF3B3B3B),
            onErrorContainer: Color(0xFFF2F2F2),
            surface: Color(0xFF000000),
            onSurface: Color(0xFFF3F3F3),
            surfaceDim: Color(0xFF000000),
            surfaceBright: Color(0xFF393939),
            surfaceContainerLowest: Color(0xFF080808),
            surfaceContainerLow: Color(0xFF1D1D1D),
            surfaceContainer: Color(0xFF242424),
            surfaceContainerHigh: Color(0xFF2B2B2B),
            surfaceContainerHighest: Color(0xFF333333),
            onSurfaceVariant: Color(0xFFBDBDBD),
            outline: Color(0xFF909090),
            outlineVariant: Color(0xFF444444),
            inverseSurface: Color(0xFFE5E5E5),
            onInverseSurface: Color(0xFF202020),
            inversePrimary: Color(0xFF555555),
            surfaceTint: Colors.transparent,
          )
        : ColorScheme.fromSeed(
            seedColor: const Color(0xFF526057),
            brightness: brightness,
          ).copyWith(
            primary: const Color(0xFF222823),
            onPrimary: const Color(0xFFF6F4EF),
            primaryContainer: const Color(0xFFE7ECE2),
            onPrimaryContainer: const Color(0xFF303D32),
            secondaryContainer: const Color(0xFFEAECE5),
            onSecondaryContainer: const Color(0xFF222823),
            surface: const Color(0xFFF6F4EF),
            onSurface: const Color(0xFF222823),
            surfaceContainerLow: const Color(0xFFFFFEFA),
            surfaceContainerHighest: const Color(0xFFEAECE5),
            onSurfaceVariant: const Color(0xFF526057),
            outline: const Color(0xFF707C72),
            outlineVariant: const Color(0xFFD5DBD4),
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
