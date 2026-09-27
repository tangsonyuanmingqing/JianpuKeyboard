import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/theme/app_theme.dart';
import 'package:jianpu_keyboard/app/theme/app_typography.dart';

void main() {
  test('the application theme defines the agreed typography scale', () {
    final theme = AppTheme.light();
    final typography = theme.extension<AppTypography>();

    expect(theme.textTheme.headlineMedium?.fontFamily, AppTypography.uiFamily);
    expect(theme.textTheme.headlineMedium?.fontSize, 28);
    expect(theme.textTheme.headlineMedium?.height, 36 / 28);
    expect(theme.textTheme.headlineMedium?.fontWeight, FontWeight.w700);
    expect(theme.textTheme.titleLarge?.fontSize, 22);
    expect(theme.textTheme.titleLarge?.height, 28 / 22);
    expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w600);
    expect(theme.textTheme.bodyLarge?.fontSize, 16);
    expect(theme.textTheme.bodyLarge?.height, 1.5);
    expect(theme.textTheme.bodyLarge?.fontWeight, FontWeight.w400);
    expect(theme.textTheme.labelLarge?.fontWeight, FontWeight.w500);
    expect(typography?.notationBody.fontFamily, AppTypography.notationFamily);
    expect(typography?.notationBody.fontSize, 16);
    expect(typography?.notationBody.height, 1.5);
    expect(typography?.notationBody.fontWeight, FontWeight.w400);
  });

  test(
      'light and dark themes give all semantic text an explicit readable color',
      () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      final typography = theme.extension<AppTypography>()!;

      expect(theme.appBarTheme.titleTextStyle?.color, scheme.onSurface);
      expect(theme.textTheme.titleLarge?.color, scheme.onSurface);
      expect(theme.textTheme.bodyMedium?.color, scheme.onSurface);
      expect(theme.listTileTheme.titleTextStyle?.color, scheme.onSurface);
      expect(theme.listTileTheme.subtitleTextStyle?.color,
          scheme.onSurfaceVariant);
      expect(typography.songTitle.color, scheme.onSurface);
      expect(typography.notationBody.color, scheme.onSurface);
      expect(_contrastRatio(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5));
    }
  });

  test('grid and inspection tokens retain their semantic weights', () {
    const typography = AppTypography.standard();

    expect(typography.gridCell.fontWeight, FontWeight.w400);
    expect(typography.gridHeader.fontWeight, FontWeight.w600);
    expect(typography.gridLabel.fontWeight, FontWeight.w500);
    expect(typography.inspectionTitle.fontWeight, FontWeight.w700);
    expect(typography.inspectionHeader.fontWeight, FontWeight.w600);
    expect(typography.inspectionCell.fontWeight, FontWeight.w400);
    expect(typography.songTitle.fontWeight, FontWeight.w700);
  });

  test('font assets and typography declarations stay centralized', () {
    expect(File('assets/fonts/NotoSansCJKsc-VF.ttf').existsSync(), isTrue);
    expect(File('assets/fonts/NotoSansMonoCJKsc-VF.ttf').existsSync(), isTrue);
    expect(File('assets/fonts/OFL-1.1.txt').existsSync(), isTrue);

    final violations = <String>[];
    final forbidden = RegExp(
      r'\bTextStyle\s*\(|\bfontFamily(?:Fallback)?\s*:|\bfontWeight\s*:|\bfontSize\s*:',
    );
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll('\\', '/');
      if (path.startsWith('lib/app/theme/')) continue;
      if (forbidden.hasMatch(file.readAsStringSync())) {
        violations.add(path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Typography belongs in lib/app/theme, not feature widgets.',
    );
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + .05) / (darker + .05);
}
