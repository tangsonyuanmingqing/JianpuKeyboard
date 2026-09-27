import 'package:flutter/material.dart';

/// Central typography tokens for every application-owned text surface.
///
/// UI content uses Noto Sans CJK SC. Text that depends on character-width
/// alignment, such as notation input and converted output, uses its mono
/// counterpart. Keep font construction in this file so future screens cannot
/// accidentally introduce a third visual language.
class AppTypography extends ThemeExtension<AppTypography> {
  static const uiFamily = 'NotoSansCJKSC';
  static const notationFamily = 'NotoSansMonoCJKSC';

  /// Match Flutter Icon typography when batching noninteractive glyph painting.
  static TextStyle iconGlyph(
          IconData icon, double size, Color color, IconThemeData theme) =>
      TextStyle(
        inherit: false,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontFamilyFallback: icon.fontFamilyFallback,
        fontSize: size,
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
        shadows: theme.shadows,
        fontVariations: [
          if (theme.fill != null) FontVariation('FILL', theme.fill!),
          if (theme.weight != null) FontVariation('wght', theme.weight!),
          if (theme.grade != null) FontVariation('GRAD', theme.grade!),
          if (theme.opticalSize != null)
            FontVariation('opsz', theme.opticalSize!),
        ],
        color: color.withValues(alpha: color.a * (theme.opacity ?? 1)),
      );

  static const _bodyLarge = TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const _bodyMedium = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  static const _bodySmall = TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  static const _labelLarge = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static const _labelMedium = TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
  );

  static const _labelSmall = TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    height: 16 / 11,
    fontWeight: FontWeight.w500,
  );

  static const _titleLarge = TextStyle(
    fontFamily: uiFamily,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
  );

  static const _titleMedium = TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
  );

  static const _titleSmall = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );

  static const _headlineLarge = TextStyle(
    fontFamily: uiFamily,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
  );

  static const _headlineMedium = TextStyle(
    fontFamily: uiFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );

  static const _headlineSmall = TextStyle(
    fontFamily: uiFamily,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
  );

  static const _notationBody = TextStyle(
    fontFamily: notationFamily,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const _songTitle = TextStyle(
    fontFamily: uiFamily,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
  );

  final TextStyle notationBody;
  final TextStyle gridCell;
  final TextStyle gridHeader;
  final TextStyle gridLabel;
  final TextStyle inspectionTitle;
  final TextStyle inspectionHeader;
  final TextStyle inspectionCell;
  final TextStyle songTitle;

  const AppTypography({
    required this.notationBody,
    required this.gridCell,
    required this.gridHeader,
    required this.gridLabel,
    required this.inspectionTitle,
    required this.inspectionHeader,
    required this.inspectionCell,
    required this.songTitle,
  });

  const AppTypography.standard()
      : notationBody = _notationBody,
        gridCell = _bodyLarge,
        gridHeader = _titleSmall,
        gridLabel = _labelMedium,
        inspectionTitle = _songTitle,
        inspectionHeader = _titleSmall,
        inspectionCell = _bodyLarge,
        songTitle = _songTitle;

  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: uiFamily,
      fontSize: 57,
      height: 64 / 57,
      fontWeight: FontWeight.w700,
    ),
    displayMedium: TextStyle(
      fontFamily: uiFamily,
      fontSize: 45,
      height: 52 / 45,
      fontWeight: FontWeight.w700,
    ),
    displaySmall: TextStyle(
      fontFamily: uiFamily,
      fontSize: 36,
      height: 44 / 36,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: _headlineLarge,
    headlineMedium: _headlineMedium,
    headlineSmall: _headlineSmall,
    titleLarge: _titleLarge,
    titleMedium: _titleMedium,
    titleSmall: _titleSmall,
    bodyLarge: _bodyLarge,
    bodyMedium: _bodyMedium,
    bodySmall: _bodySmall,
    labelLarge: _labelLarge,
    labelMedium: _labelMedium,
    labelSmall: _labelSmall,
  );

  /// Resolves the shared typography against the current surface foreground.
  ///
  /// Font tokens remain colorless above so export renderers can choose their
  /// own fixed palette. Application widgets receive the themed version below.
  static TextTheme textThemeFor(Color foreground) =>
      textTheme.apply(displayColor: foreground, bodyColor: foreground);

  factory AppTypography.forColorScheme(ColorScheme colorScheme) {
    final foreground = colorScheme.onSurface;
    return AppTypography(
      notationBody: _notationBody.copyWith(color: foreground),
      gridCell: _bodyLarge.copyWith(color: foreground),
      gridHeader: _titleSmall.copyWith(color: foreground),
      gridLabel: _labelMedium.copyWith(color: colorScheme.onSurfaceVariant),
      inspectionTitle: _songTitle.copyWith(color: foreground),
      inspectionHeader: _titleSmall.copyWith(color: foreground),
      inspectionCell: _bodyLarge.copyWith(color: foreground),
      songTitle: _songTitle.copyWith(color: foreground),
    );
  }

  static AppTypography of(BuildContext context) =>
      Theme.of(context).extension<AppTypography>() ??
      const AppTypography.standard();

  TextStyle gridCellAt(double fontSize) =>
      gridCell.copyWith(fontSize: fontSize);

  TextStyle gridHeaderAt(double fontSize) =>
      gridHeader.copyWith(fontSize: fontSize);

  TextStyle inspectionCellAt(double fontSize) =>
      inspectionCell.copyWith(fontSize: fontSize);

  @override
  AppTypography copyWith({
    TextStyle? notationBody,
    TextStyle? gridCell,
    TextStyle? gridHeader,
    TextStyle? gridLabel,
    TextStyle? inspectionTitle,
    TextStyle? inspectionHeader,
    TextStyle? inspectionCell,
    TextStyle? songTitle,
  }) =>
      AppTypography(
        notationBody: notationBody ?? this.notationBody,
        gridCell: gridCell ?? this.gridCell,
        gridHeader: gridHeader ?? this.gridHeader,
        gridLabel: gridLabel ?? this.gridLabel,
        inspectionTitle: inspectionTitle ?? this.inspectionTitle,
        inspectionHeader: inspectionHeader ?? this.inspectionHeader,
        inspectionCell: inspectionCell ?? this.inspectionCell,
        songTitle: songTitle ?? this.songTitle,
      );

  @override
  AppTypography lerp(covariant AppTypography? other, double t) {
    if (other == null) return this;
    return AppTypography(
      notationBody: TextStyle.lerp(notationBody, other.notationBody, t)!,
      gridCell: TextStyle.lerp(gridCell, other.gridCell, t)!,
      gridHeader: TextStyle.lerp(gridHeader, other.gridHeader, t)!,
      gridLabel: TextStyle.lerp(gridLabel, other.gridLabel, t)!,
      inspectionTitle:
          TextStyle.lerp(inspectionTitle, other.inspectionTitle, t)!,
      inspectionHeader:
          TextStyle.lerp(inspectionHeader, other.inspectionHeader, t)!,
      inspectionCell: TextStyle.lerp(inspectionCell, other.inspectionCell, t)!,
      songTitle: TextStyle.lerp(songTitle, other.songTitle, t)!,
    );
  }
}
