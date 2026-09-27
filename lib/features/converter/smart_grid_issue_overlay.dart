import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_typography.dart';
import 'smart_grid_validation.dart';
import 'table_scale.dart';

/// Paints a row's noninteractive issue glyphs without one Icon layout per cell.
/// Borders, tooltips, editing and semantics remain owned by the cells.
class SmartGridIssueOverlay extends StatelessWidget {
  const SmartGridIssueOverlay({
    super.key,
    required this.issues,
    required this.leadingWidth,
    required this.scale,
    required this.child,
  });

  final List<SmartGridIssue> issues;
  final double leadingWidth;
  final TableScale scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final iconSize = theme.applyTextScaling == true
        ? MediaQuery.textScalerOf(context).scale(13)
        : 13.0;
    TextStyle style(IconData icon, Color color) =>
        AppTypography.iconGlyph(icon, iconSize, color, theme);
    return CustomPaint(
      foregroundPainter: issues.isEmpty
          ? null
          : _IssuePainter(
              issues,
              leadingWidth,
              scale.dimension(58),
              scale.dimension(3) +
                  2, // Match the cell's padding plus 2px issue border.
              iconSize,
              Directionality.of(context),
              style(Icons.error, Theme.of(context).colorScheme.error),
              style(Icons.warning_amber_rounded, Colors.amber.shade800),
            ),
      child: child,
    );
  }
}

class _IssuePainter extends CustomPainter {
  _IssuePainter(this.issues, this.leadingWidth, this.cellSize, this.inset,
      this.iconSize, this.direction, this.errorStyle, this.warningStyle);

  final List<SmartGridIssue> issues;
  final double leadingWidth, cellSize, inset, iconSize;
  final TextDirection direction;
  final TextStyle errorStyle, warningStyle;

  @override
  void paint(Canvas canvas, Size size) {
    // At most two glyph layouts per row, independent of its number of errors.
    final glyphs = <SmartGridIssueSeverity, TextPainter>{};
    try {
      for (final issue in issues) {
        final glyph = glyphs.putIfAbsent(issue.severity, () {
          final error = issue.severity == SmartGridIssueSeverity.error;
          return TextPainter(
            textDirection: direction,
            text: TextSpan(
              text: String.fromCharCode(
                  (error ? Icons.error : Icons.warning_amber_rounded)
                      .codePoint),
              style: error ? errorStyle : warningStyle,
            ),
          )..layout(maxWidth: iconSize);
        });
        glyph.paint(
          canvas,
          Offset(
            leadingWidth +
                (issue.column + 1) * cellSize -
                inset -
                iconSize +
                (iconSize - glyph.width) / 2,
            inset + (iconSize - glyph.height) / 2,
          ),
        );
      }
    } finally {
      for (final glyph in glyphs.values) {
        glyph.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IssuePainter oldDelegate) =>
      leadingWidth != oldDelegate.leadingWidth ||
      cellSize != oldDelegate.cellSize ||
      inset != oldDelegate.inset ||
      iconSize != oldDelegate.iconSize ||
      direction != oldDelegate.direction ||
      errorStyle != oldDelegate.errorStyle ||
      warningStyle != oldDelegate.warningStyle ||
      !listEquals(issues, oldDelegate.issues);
}
