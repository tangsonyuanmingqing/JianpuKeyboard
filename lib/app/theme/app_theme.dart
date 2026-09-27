import 'package:flutter/material.dart';

import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF2F6FED);

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFFFFBFF),
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF1C1B20),
          onSurfaceVariant: const Color(0xFF49454F),
        ),
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF141218),
          surfaceContainerLowest: const Color(0xFF0F0D13),
          onSurface: const Color(0xFFE6E1E9),
          onSurfaceVariant: const Color(0xFFCAC4D0),
        ),
      );

  static ThemeData _build(ColorScheme colorScheme) {
    final textTheme = AppTypography.textThemeFor(colorScheme.onSurface);
    final typography = AppTypography.forColorScheme(colorScheme);
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: AppTypography.uiFamily,
      textTheme: textTheme,
      extensions: [typography],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: colorScheme.surface,
        selectedTileColor: colorScheme.primaryContainer,
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
        selectedColor: colorScheme.primary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainer,
        textStyle: textTheme.labelLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        helperStyle:
            textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: colorScheme.onPrimary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
      ),
    );
  }
}
